#include "MetalSprocketsAddOnsShaders.h"
#include "ShadowMap.h"

using namespace metal;

namespace ShadowMask {

    constant bool DEBUG [[function_constant(0)]];
    // True when a world-space shading normal texture is bound.
    constant bool HAS_NORMALS [[function_constant(1)]];

    // Light-space depth of a world position.
    float lightDepth(constant ShadowLightParameters &light, float3 position) {
        float4 clip = light.lightViewProjectionMatrix * float4(position, 1.0);
        return clip.z / clip.w;
    }

    // Shadow factor with a smooth shading normal: surfaces facing away from a light are in its shadow, and lookups
    // move off the surface along the normal by about a shadow map texel, so flat triangles do not shadow themselves.
    float sampleShadowWithNormal(
        float3 position,
        float3 normal,
        constant ShadowMapParameters &shadowParams,
        depth2d_array<float, access::sample> shadowMap,
        sampler shadowSampler
    ) {
        float combined = 1.0;
        for (int i = 0; i < shadowParams.lightCount; i++) {
            constant ShadowLightParameters &light = shadowParams.lights[i];
            // World size of one texel: the light's x clip axis spans 2 over mapSize texels.
            float4x4 matrix = light.lightViewProjectionMatrix;
            float3 xAxis = float3(matrix[0][0], matrix[1][0], matrix[2][0]);
            float texel = 2.0 / (shadowParams.mapSize * max(length(xAxis), 1e-6));
            float depthChange = lightDepth(light, position + normal * texel) - lightDepth(light, position);
            bool facesLight = shadowParams.reverseZ != 0 ? depthChange > 0.0 : depthChange < 0.0;
            if (!facesLight) {
                return 0.0;
            }
            combined *= ShadowMap::sampleShadowForLight(position + normal * (1.5 * texel), light, shadowParams.mapSize, shadowMap, shadowSampler, uint(i));
        }
        return combined;
    }

    [[kernel]] void shadow_mask_compute(
        uint2 tid [[thread_position_in_grid]],
        depth2d<float, access::read> sceneDepth [[texture(0)]],
        depth2d_array<float, access::sample> shadowMapTexture [[texture(1)]],
        texture2d<float, access::read_write> outputTexture [[texture(2)]],
        texture2d<float, access::read> sceneNormals [[texture(3), function_constant(HAS_NORMALS)]],
        sampler shadowMapSampler [[sampler(0)]],
        constant ShadowMaskParameters &params [[buffer(0)]],
        constant ShadowMapParameters &shadowMapParams [[buffer(1)]]
    ) {
        uint2 outputSize = uint2(outputTexture.get_width(), outputTexture.get_height());
        if (tid.x >= outputSize.x || tid.y >= outputSize.y) {
            return;
        }

        // The depth texture may be a different size to the output texture.
        uint2 depthSize = uint2(sceneDepth.get_width(), sceneDepth.get_height());
        uint2 depthCoord = uint2(
            uint(float(tid.x) * float(depthSize.x) / float(outputSize.x)),
            uint(float(tid.y) * float(depthSize.y) / float(outputSize.y))
        );
        float depth = sceneDepth.read(depthCoord);

        // Skip background (depth at clear value — 0.0 for inverse Z, 1.0 for standard)
        if (depth == 0.0 || depth == 1.0) {
            return;
        }

        // Reconstruct world position from screen UV + depth
        float2 texCoord = (float2(tid) + 0.5) / float2(outputSize);
        float2 ndc = texCoord * 2.0 - 1.0;
        ndc.y = -ndc.y; // flip Y for Metal NDC
        float4 clipPos = float4(ndc, depth, 1.0);
        float4 worldPos = params.inverseViewProjection * clipPos;
        worldPos /= worldPos.w;

        float3 normal = 0;
        if (HAS_NORMALS) {
            float3 stored = sceneNormals.read(depthCoord).xyz;
            if (length_squared(stored) > 0.25) {
                normal = normalize(stored);
            }
        }
        float shadowFactor = any(normal != 0)
            ? sampleShadowWithNormal(worldPos.xyz, normal, shadowMapParams, shadowMapTexture, shadowMapSampler)
            : ShadowMap::sampleShadow(worldPos.xyz, shadowMapParams, shadowMapTexture, shadowMapSampler);

        if (shadowFactor >= 1.0) {
            return; // Fully lit — leave the pixel alone.
        }

        float darkness = params.shadowIntensity * (1.0 - shadowFactor);
        float4 existing = outputTexture.read(tid);
        if (DEBUG) {
            existing.rgb = mix(existing.rgb, float3(1.0, 0.0, 1.0), darkness);
        } else {
            existing.rgb *= 1.0 - darkness;
        }
        outputTexture.write(existing, tid);
    }

}
