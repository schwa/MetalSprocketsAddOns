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
    // Metal requires a fragment function in the pipeline descriptor,
    // but for shadow maps we only need the depth output from the vertex stage.
    [[fragment]] void fragment_depth() {
    }

    // MARK: - Shadow sampling utility

    /// Computes shadow visibility for a world-space position.
    /// Returns 1.0 if fully lit, 0.0 if fully shadowed.
    /// Uses PCF (percentage-closer filtering) with a 3×3 kernel for soft edges.
    float sampleShadow(
        float3 worldPosition,
        constant ShadowMapParameters &shadowParams,
        depth2d<float, access::sample> shadowMap,
        sampler shadowSampler
    ) {
        // Transform world position into light clip space
        float4 lightClip = shadowParams.lightViewProjectionMatrix * float4(worldPosition, 1.0);
        float3 lightNDC = lightClip.xyz / lightClip.w;

        // Convert from NDC [-1,1] to texture coordinates [0,1]
        // Metal NDC: x,y in [-1,1], z in [0,1] (reverse-Z depends on projection)
        float2 shadowUV = lightNDC.xy * 0.5 + 0.5;
        shadowUV.y = 1.0 - shadowUV.y; // Flip Y for texture coordinates

        float currentDepth = lightNDC.z;

        // Out-of-bounds check — fragments outside the shadow map are fully lit
        if (shadowUV.x < 0.0 || shadowUV.x > 1.0 || shadowUV.y < 0.0 || shadowUV.y > 1.0) {
            return 1.0;
        }
        if (currentDepth > 1.0 || currentDepth < 0.0) {
            return 1.0;
        }

        // PCF 3×3 kernel using sample_compare
        // sampler compareFunction is .lessEqual → returns 1.0 when storedDepth <= compareDepth
        // storedDepth <= currentDepth means nothing closer blocks the light → lit
        float shadow = 0.0;
        float texelSize = 1.0 / shadowParams.mapSize;
        float compareDepth = currentDepth - shadowParams.bias;
        for (int x = -1; x <= 1; x++) {
            for (int y = -1; y <= 1; y++) {
                float2 offset = float2(float(x), float(y)) * texelSize;
                shadow += shadowMap.sample_compare(shadowSampler, shadowUV + offset, compareDepth);
            }
        }
        return shadow / 9.0;
    }

} // namespace ShadowMap
