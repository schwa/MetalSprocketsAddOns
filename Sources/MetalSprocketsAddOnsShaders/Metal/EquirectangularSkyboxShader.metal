#include "MetalSprocketsAddOnsShaders.h"

using namespace metal;

namespace EquirectangularSkyboxShader {

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

    // Convert a normalized world-space direction to equirectangular (lat-long) UVs.
    //   u = (atan2(x, -z) / pi + 1) / 2     // longitude, wrapping at the seam
    //   v = 1 - (asin(y) / pi + 0.5)        // latitude, V=0 at top (+Y), V=1 at bottom (-Y)
    static inline float2 direction_to_equirectangular_uv(float3 d) {
        float u = (atan2(d.x, -d.z) / M_PI_F + 1.0) * 0.5;
        float v = 1.0 - (asin(clamp(d.y, -1.0, 1.0)) / M_PI_F + 0.5);
        return float2(u, v);
    }

    [[fragment]] float4 fragment_main(
        VertexOut in [[stage_in]],
        constant float4x4 &inverseViewProjectionMatrix [[buffer(0)]],
        constant float &brightness [[buffer(1)]],
        texture2d<float, access::sample> texture [[texture(0)]]
    ) {
        constexpr sampler s(mag_filter::linear, min_filter::linear, s_address::repeat, t_address::clamp_to_edge);

        // Unproject from clip space to world-space direction
        float4 clipPos = float4(in.uv.x * 2.0 - 1.0, in.uv.y * 2.0 - 1.0, 1.0, 1.0);
        float4 worldPos = inverseViewProjectionMatrix * clipPos;
        float3 direction = normalize(worldPos.xyz / worldPos.w);

        float2 uv = direction_to_equirectangular_uv(direction);
        float4 color = texture.sample(s, uv);
        return float4(color.rgb * brightness, color.a);
    }

} // namespace EquirectangularSkyboxShader
