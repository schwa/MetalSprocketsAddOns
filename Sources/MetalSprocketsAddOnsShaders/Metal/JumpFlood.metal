#include "MetalSprocketsAddOnsShaders.h"
#include "JumpFlood.h"

using namespace metal;

// Jump flood outlines, after https://bgolus.medium.com/the-quest-for-very-wide-outlines-ba82ed442cd9
// Seed textures hold the pixel position of the nearest masked pixel, or -1 when none is known yet.
namespace JumpFlood {

    constant float2 noSeed = float2(-1.0);

    [[kernel]] void init_seeds(
        uint2 tid [[thread_position_in_grid]],
        texture2d<float, access::read> mask [[texture(0)]],
        texture2d<float, access::write> seeds [[texture(1)]]
    ) {
        if (tid.x >= seeds.get_width() || tid.y >= seeds.get_height()) {
            return;
        }
        float2 seed = mask.read(tid).r >= 0.5 ? float2(tid) : noSeed;
        seeds.write(float4(seed, 0, 0), tid);
    }

    // One separable flood step: keep the nearest of the seeds at -offset, 0 and +offset.
    [[kernel]] void flood_step(
        uint2 tid [[thread_position_in_grid]],
        texture2d<float, access::read> source [[texture(0)]],
        texture2d<float, access::write> destination [[texture(1)]],
        constant JumpFloodStepParameters &params [[buffer(0)]]
    ) {
        int2 size = int2(destination.get_width(), destination.get_height());
        int2 position = int2(tid);
        if (position.x >= size.x || position.y >= size.y) {
            return;
        }
        float2 best = noSeed;
        float bestDistance = INFINITY;
        for (int i = -1; i <= 1; i++) {
            int2 samplePosition = position + params.offset * i;
            if (any(samplePosition < 0) || any(samplePosition >= size)) {
                continue;
            }
            float2 seed = source.read(uint2(samplePosition)).xy;
            if (seed.x < 0) {
                continue;
            }
            float distance = length_squared(seed - float2(position));
            if (distance < bestDistance) {
                bestDistance = distance;
                best = seed;
            }
        }
        destination.write(float4(best, 0, 0), tid);
    }

    struct VertexOut {
        float4 position [[position]];
    };

    [[vertex]] VertexOut outline_vertex(uint vertexID [[vertex_id]]) {
        float2 uv = float2((vertexID << 1) & 2, vertexID & 2);
        VertexOut out;
        out.position = float4(uv * 2.0 - 1.0, 0.0, 1.0);
        return out;
    }

    [[fragment]] float4 outline_fragment(
        VertexOut in [[stage_in]],
        texture2d<float, access::read> mask [[texture(0)]],
        texture2d<float, access::read> seeds [[texture(1)]],
        constant JumpFloodOutlineParameters &params [[buffer(0)]]
    ) {
        uint2 pixel = uint2(in.position.xy);
        if (pixel.x >= seeds.get_width() || pixel.y >= seeds.get_height() || mask.read(pixel).r >= 0.5) {
            discard_fragment();
        }
        float2 seed = seeds.read(pixel).xy;
        if (seed.x < 0) {
            discard_fragment();
        }
        // Seeds are pixel centres; the mask edge is half a pixel past the nearest one.
        float edgeDistance = length(seed - float2(pixel)) - 0.5;
        float coverage = saturate(params.width - edgeDistance + 0.5);
        if (coverage <= 0) {
            discard_fragment();
        }
        return float4(params.color.rgb, params.color.a * coverage);
    }

} // namespace JumpFlood
