#include "MetalSprocketsAddOnsShaders.h"

using namespace metal;

namespace ShadowMap {

    // MARK: - Depth-only pass (renders geometry from light's POV)

    struct VertexIn {
        float3 position [[attribute(0)]];
    };

    struct VertexOut {
        float4 position [[position]];
    };

    [[vertex]] VertexOut vertex_depth(
        VertexIn in [[stage_in]],
        constant float4x4 &lightViewProjectionMatrix [[buffer(1)]],
        constant float4x4 &modelMatrix [[buffer(2)]]
    ) {
        VertexOut out;
        out.position = lightViewProjectionMatrix * modelMatrix * float4(in.position, 1.0);
        return out;
    }

    // Empty fragment shader for depth-only rendering.
    [[fragment]] void fragment_depth() {
    }

    // MARK: - Shadow sampling utility

    /// Samples shadow factor for a single light at a given array slice.
    float sampleShadowForLight(
        float3 worldPosition,
        constant ShadowLightParameters &light,
        float mapSize,
        depth2d_array<float, access::sample> shadowMap,
        sampler shadowSampler,
        uint sliceIndex
    ) {
        // Transform world position into light clip space
        float4 lightClip = light.lightViewProjectionMatrix * float4(worldPosition, 1.0);
        float3 lightNDC = lightClip.xyz / lightClip.w;

        // Convert from NDC [-1,1] to texture coordinates [0,1]
        float2 shadowUV = lightNDC.xy * 0.5 + 0.5;
        shadowUV.y = 1.0 - shadowUV.y;

        float currentDepth = lightNDC.z;

        // Out-of-bounds check — fragments outside the shadow map are fully lit
        if (shadowUV.x < 0.0 || shadowUV.x > 1.0 || shadowUV.y < 0.0 || shadowUV.y > 1.0) {
            return 1.0;
        }
        if (currentDepth > 1.0 || currentDepth < 0.0) {
            return 1.0;
        }

        // PCF 3×3 kernel using sample_compare
        float shadow = 0.0;
        float texelSize = 1.0 / mapSize;
        float compareDepth = currentDepth;
        for (int x = -1; x <= 1; x++) {
            for (int y = -1; y <= 1; y++) {
                float2 offset = float2(float(x), float(y)) * texelSize;
                shadow += shadowMap.sample_compare(shadowSampler, shadowUV + offset, sliceIndex, compareDepth);
            }
        }
        return shadow / 9.0;
    }

    /// Computes combined shadow visibility across all shadow-casting lights.
    /// Returns 1.0 if fully lit by all lights, 0.0 if fully shadowed by all.
    /// Shadow factors are multiplied: a fragment must be lit by ALL lights to be fully lit.
    float sampleShadow(
        float3 worldPosition,
        constant ShadowMapParameters &shadowParams,
        depth2d_array<float, access::sample> shadowMap,
        sampler shadowSampler
    ) {
        float combinedShadow = 1.0;
        for (int i = 0; i < shadowParams.lightCount; i++) {
            float factor = sampleShadowForLight(
                worldPosition,
                shadowParams.lights[i],
                shadowParams.mapSize,
                shadowMap,
                shadowSampler,
                uint(i)
            );
            combinedShadow *= factor;
        }
        return combinedShadow;
    }

} // namespace ShadowMap
