#include "MetalSprocketsAddOnsShaders.h"
#include "GaussianBlur.h"

using namespace metal;

namespace GaussianBlur {

    // One 1D pass of a separable Gaussian blur. `weights` holds radius + 1 values, centre tap first.
    [[kernel]] void blur_pass(
        uint2 tid [[thread_position_in_grid]],
        texture2d<float, access::read> source [[texture(0)]],
        texture2d<float, access::write> destination [[texture(1)]],
        constant float *weights [[buffer(0)]],
        constant GaussianBlurParameters &params [[buffer(1)]]
    ) {
        int2 size = int2(destination.get_width(), destination.get_height());
        if (int(tid.x) >= size.x || int(tid.y) >= size.y) {
            return;
        }
        int2 sourceSize = int2(source.get_width(), source.get_height());
        int2 position = int2(tid);
        float4 sum = 0;
        for (int offset = -params.radius; offset <= params.radius; offset++) {
            int2 samplePosition = position + params.direction * offset;
            float weight = weights[abs(offset)];
            bool outside = any(samplePosition < 0) || any(samplePosition >= sourceSize);
            if (outside) {
                if (params.edgeMode == 1) {
                    continue;
                }
                samplePosition = clamp(samplePosition, int2(0), sourceSize - 1);
            }
            sum += weight * source.read(uint2(samplePosition));
        }
        destination.write(sum, tid);
    }

    // Box-averages `factor` source pixels along `direction` into one output pixel. A partial last block averages only the pixels inside the source.
    [[kernel]] void fast_blur_downsample(
        uint2 tid [[thread_position_in_grid]],
        texture2d<float, access::read> source [[texture(0)]],
        texture2d<float, access::write> destination [[texture(1)]],
        constant FastBlurDownsampleParameters &params [[buffer(0)]]
    ) {
        int2 size = int2(destination.get_width(), destination.get_height());
        if (int(tid.x) >= size.x || int(tid.y) >= size.y) {
            return;
        }
        int2 sourceSize = int2(source.get_width(), source.get_height());
        int2 start = int2(tid) * (int2(1) + params.direction * (params.factor - 1));
        float4 sum = 0;
        int count = 0;
        for (int offset = 0; offset < params.factor; offset++) {
            int2 position = start + params.direction * offset;
            if (any(position >= sourceSize)) {
                break;
            }
            sum += source.read(uint2(position));
            count++;
        }
        destination.write(sum / float(max(count, 1)), tid);
    }

    // Taps along one axis for reconstructing at low-resolution coordinate `u` (texel units). Returns the tap count.
    static int upsampleTaps(float u, int lowSize, bool bSpline, thread float2 &positions, thread float2 &weights) {
        if (!bSpline) {
            positions = float2(u / float(lowSize), 0);
            weights = float2(1, 0);
            return 1;
        }
        // Cubic B-spline as two bilinear taps (Sigg and Hadwiger).
        float t = u - 0.5;
        float i = floor(t);
        float f = t - i;
        float f2 = f * f;
        float f3 = f2 * f;
        float w0 = (1 - 3 * f + 3 * f2 - f3) / 6;
        float w1 = (4 - 6 * f2 + 3 * f3) / 6;
        float w2 = (1 + 3 * f + 3 * f2 - 3 * f3) / 6;
        float w3 = f3 / 6;
        float g0 = w0 + w1;
        float g1 = w2 + w3;
        positions = (float2(i - 1 + w1 / g0, i + 1 + w3 / g1) + 0.5) / float(lowSize);
        weights = float2(g0, g1);
        return 2;
    }

    // Reconstructs the full-resolution image from the blurred low-resolution image.
    [[kernel]] void fast_blur_upsample(
        uint2 tid [[thread_position_in_grid]],
        texture2d<float, access::sample> source [[texture(0)]],
        texture2d<float, access::write> destination [[texture(1)]],
        constant FastBlurUpsampleParameters &params [[buffer(0)]]
    ) {
        int2 size = int2(destination.get_width(), destination.get_height());
        if (int(tid.x) >= size.x || int(tid.y) >= size.y) {
            return;
        }
        constexpr sampler linearSampler(coord::normalized, filter::linear, address::clamp_to_edge);
        int2 lowSize = int2(source.get_width(), source.get_height());
        float2 u = (float2(tid) + 0.5) / float2(params.factor);
        float2 positionsX, weightsX, positionsY, weightsY;
        int countX = upsampleTaps(u.x, lowSize.x, params.bSpline.x != 0, positionsX, weightsX);
        int countY = upsampleTaps(u.y, lowSize.y, params.bSpline.y != 0, positionsY, weightsY);
        float4 sum = 0;
        for (int y = 0; y < countY; y++) {
            for (int x = 0; x < countX; x++) {
                sum += weightsX[x] * weightsY[y] * source.sample(linearSampler, float2(positionsX[x], positionsY[y]));
            }
        }
        destination.write(sum, tid);
    }

} // namespace GaussianBlur
