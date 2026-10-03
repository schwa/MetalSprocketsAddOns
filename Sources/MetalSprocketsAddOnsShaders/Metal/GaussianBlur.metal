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

} // namespace GaussianBlur
