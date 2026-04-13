#include "MetalSprocketsAddOnsShaders.h"

using namespace metal;

namespace SkyboxShader {

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    // Fullscreen triangle: 3 vertices cover the entire screen
    [[vertex]] VertexOut vertex_main(
        uint vertex_id [[vertex_id]],
        constant float4x4 &inverseViewProjectionMatrix [[buffer(0)]]
    ) {
        VertexOut out;
        // Generate oversized triangle covering the full clip space
        float2 uv = float2((vertex_id << 1) & 2, vertex_id & 2);
        out.position = float4(uv * 2.0 - 1.0, 1.0, 1.0);
        out.uv = uv;
        return out;
    }

    [[fragment]] float4 fragment_main(
        VertexOut in [[stage_in]],
        constant float4x4 &inverseViewProjectionMatrix [[buffer(0)]],
        texturecube<float, access::sample> texture [[texture(0)]]
    ) {
        constexpr sampler s(mag_filter::linear, min_filter::linear);

        // Unproject from clip space to world-space direction
        float4 clipPos = float4(in.uv.x * 2.0 - 1.0, in.uv.y * 2.0 - 1.0, 1.0, 1.0);
        float4 worldPos = inverseViewProjectionMatrix * clipPos;
        float3 direction = normalize(worldPos.xyz / worldPos.w);

        return texture.sample(s, direction);
    }

} // namespace SkyboxShader
