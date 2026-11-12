#include "MetalSprocketsAddOnsShaders.h"
#include "JumpFlood.h"

using namespace metal;

// Jump flood outlines, after https://bgolus.medium.com/the-quest-for-very-wide-outlines-ba82ed442cd9
// Seed textures hold the pixel position of the nearest masked pixel, or -1 when none is known yet.
//
// Every function comes in a 2D variant and an `_array` variant for layered (stereo) textures, one slice per eye.
// Compute grids use z as the slice.
namespace JumpFlood {

    constant float2 noSeed = float2(-1.0);

    // Uniform access to 2D and 2D array textures, by slice.
    template <access A>
    float4 readTexel(texture2d<float, A> texture, uint2 position, uint) { return texture.read(position); }
    template <access A>
    float4 readTexel(texture2d_array<float, A> texture, uint2 position, uint slice) { return texture.read(position, slice); }
    inline void writeTexel(texture2d<float, access::write> texture, float4 value, uint2 position, uint) { texture.write(value, position); }
    inline void writeTexel(texture2d_array<float, access::write> texture, float4 value, uint2 position, uint slice) { texture.write(value, position, slice); }

    template <typename ReadTexture, typename WriteTexture>
    void initSeeds(uint3 tid, ReadTexture mask, WriteTexture seeds) {
        if (tid.x >= seeds.get_width() || tid.y >= seeds.get_height()) {
            return;
        }
        float2 seed = readTexel(mask, tid.xy, tid.z).r >= 0.5 ? float2(tid.xy) : noSeed;
        writeTexel(seeds, float4(seed, 0, 0), tid.xy, tid.z);
    }

    [[kernel]] void init_seeds(
        uint3 tid [[thread_position_in_grid]],
        texture2d<float, access::read> mask [[texture(0)]],
        texture2d<float, access::write> seeds [[texture(1)]]
    ) {
        initSeeds(tid, mask, seeds);
    }

    [[kernel]] void init_seeds_array(
        uint3 tid [[thread_position_in_grid]],
        texture2d_array<float, access::read> mask [[texture(0)]],
        texture2d_array<float, access::write> seeds [[texture(1)]]
    ) {
        initSeeds(tid, mask, seeds);
    }

    // One separable flood step: keep the nearest of the seeds at -offset, 0 and +offset.
    template <typename ReadTexture, typename WriteTexture>
    void floodStep(uint3 tid, ReadTexture source, WriteTexture destination, int2 offset) {
        int2 size = int2(destination.get_width(), destination.get_height());
        int2 position = int2(tid.xy);
        if (position.x >= size.x || position.y >= size.y) {
            return;
        }
        float2 best = noSeed;
        float bestDistance = INFINITY;
        for (int i = -1; i <= 1; i++) {
            int2 samplePosition = position + offset * i;
            if (any(samplePosition < 0) || any(samplePosition >= size)) {
                continue;
            }
            float2 seed = readTexel(source, uint2(samplePosition), tid.z).xy;
            if (seed.x < 0) {
                continue;
            }
            float distance = length_squared(seed - float2(position));
            if (distance < bestDistance) {
                bestDistance = distance;
                best = seed;
            }
        }
        writeTexel(destination, float4(best, 0, 0), tid.xy, tid.z);
    }

    [[kernel]] void flood_step(
        uint3 tid [[thread_position_in_grid]],
        texture2d<float, access::read> source [[texture(0)]],
        texture2d<float, access::write> destination [[texture(1)]],
        constant JumpFloodStepParameters &params [[buffer(0)]]
    ) {
        floodStep(tid, source, destination, params.offset);
    }

    [[kernel]] void flood_step_array(
        uint3 tid [[thread_position_in_grid]],
        texture2d_array<float, access::read> source [[texture(0)]],
        texture2d_array<float, access::write> destination [[texture(1)]],
        constant JumpFloodStepParameters &params [[buffer(0)]]
    ) {
        floodStep(tid, source, destination, params.offset);
    }

    struct VertexOut {
        float4 position [[position]];
        uint eye [[flat]];
    };

    // A full-screen triangle, amplified once per eye when stereo.
    [[vertex]] VertexOut outline_vertex(uint vertexID [[vertex_id]], ushort eye [[amplification_id]]) {
        float2 uv = float2((vertexID << 1) & 2, vertexID & 2);
        VertexOut out;
        out.position = float4(uv * 2.0 - 1.0, 0.0, 1.0);
        out.eye = eye;
        return out;
    }

    struct OutlineOut {
        float4 color [[color(0)]];
        float depth [[depth(any)]];
    };

    // The outline takes the depth of the nearest masked pixel, so depth testing against the scene hides it behind
    // whatever is in front of the masked object.
    template <typename Texture>
    OutlineOut outline(VertexOut in, Texture mask, Texture seeds, constant JumpFloodOutlineParameters &params) {
        uint2 pixel = uint2(in.position.xy);
        uint slice = in.eye;
        if (pixel.x >= seeds.get_width() || pixel.y >= seeds.get_height() || readTexel(mask, pixel, slice).r >= 0.5) {
            discard_fragment();
        }
        float2 seed = readTexel(seeds, pixel, slice).xy;
        if (seed.x < 0) {
            discard_fragment();
        }
        // Seeds are pixel centres; the mask edge is half a pixel past the nearest one.
        float edgeDistance = length(seed - float2(pixel)) - 0.5;
        float coverage = saturate(params.width - edgeDistance + 0.5);
        if (coverage <= 0) {
            discard_fragment();
        }
        return { float4(params.color.rgb, params.color.a * coverage), readTexel(mask, uint2(seed), slice).g };
    }

    [[fragment]] OutlineOut outline_fragment(
        VertexOut in [[stage_in]],
        texture2d<float, access::read> mask [[texture(0)]],
        texture2d<float, access::read> seeds [[texture(1)]],
        constant JumpFloodOutlineParameters &params [[buffer(0)]]
    ) {
        return outline(in, mask, seeds, params);
    }

    [[fragment]] OutlineOut outline_fragment_array(
        VertexOut in [[stage_in]],
        texture2d_array<float, access::read> mask [[texture(0)]],
        texture2d_array<float, access::read> seeds [[texture(1)]],
        constant JumpFloodOutlineParameters &params [[buffer(0)]]
    ) {
        return outline(in, mask, seeds, params);
    }

} // namespace JumpFlood
