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

    // The depth texture may be a different size to the output texture.
    uint2 depthCoordinate(uint2 tid, uint2 outputSize, uint2 depthSize) {
        return uint2(
            uint(float(tid.x) * float(depthSize.x) / float(outputSize.x)),
            uint(float(tid.y) * float(depthSize.y) / float(outputSize.y))
        );
    }

    // How much to darken one pixel (0 = leave it alone). `storedNormal` is zero when there is none.
    float darkness(
        uint2 tid,
        uint2 outputSize,
        float depth,
        float3 storedNormal,
        float4x4 inverseViewProjection,
        constant ShadowMaskParameters &params,
        constant ShadowMapParameters &shadowMapParams,
        depth2d_array<float, access::sample> shadowMapTexture,
        sampler shadowMapSampler
    ) {
        // Skip background (depth at clear value — 0.0 for inverse Z, 1.0 for standard)
        if (depth == 0.0 || depth == 1.0) {
            return 0.0;
        }

        // Reconstruct world position from screen UV + depth
        float2 texCoord = (float2(tid) + 0.5) / float2(outputSize);
        float2 ndc = texCoord * 2.0 - 1.0;
        ndc.y = -ndc.y; // flip Y for Metal NDC
        float4 worldPos = inverseViewProjection * float4(ndc, depth, 1.0);
        worldPos /= worldPos.w;

        float shadowFactor = length_squared(storedNormal) > 0.25
            ? sampleShadowWithNormal(worldPos.xyz, normalize(storedNormal), shadowMapParams, shadowMapTexture, shadowMapSampler)
            : ShadowMap::sampleShadow(worldPos.xyz, shadowMapParams, shadowMapTexture, shadowMapSampler);
        return params.shadowIntensity * (1.0 - min(shadowFactor, 1.0));
    }

    float4 darken(float4 existing, float amount) {
        if (DEBUG) {
            existing.rgb = mix(existing.rgb, float3(1.0, 0.0, 1.0), amount);
        } else {
            existing.rgb *= 1.0 - amount;
        }
        return existing;
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
        uint2 depthCoord = depthCoordinate(tid, outputSize, uint2(sceneDepth.get_width(), sceneDepth.get_height()));
        float3 normal = HAS_NORMALS ? sceneNormals.read(depthCoord).xyz : float3(0);
        float amount = darkness(tid, outputSize, sceneDepth.read(depthCoord), normal, params.inverseViewProjection, params, shadowMapParams, shadowMapTexture, shadowMapSampler);
        if (amount > 0.0) {
            outputTexture.write(darken(outputTexture.read(tid), amount), tid);
        }
    }

    // One view per array slice (for example both eyes of a visionOS immersive space); the grid's z is the slice.
    [[kernel]] void shadow_mask_compute_layered(
        uint3 tid [[thread_position_in_grid]],
        depth2d_array<float, access::read> sceneDepth [[texture(0)]],
        depth2d_array<float, access::sample> shadowMapTexture [[texture(1)]],
        texture2d_array<float, access::read_write> outputTexture [[texture(2)]],
        texture2d_array<float, access::read> sceneNormals [[texture(3), function_constant(HAS_NORMALS)]],
        sampler shadowMapSampler [[sampler(0)]],
        constant ShadowMaskParameters &params [[buffer(0)]],
        constant ShadowMapParameters &shadowMapParams [[buffer(1)]],
        constant float4x4 *inverseViewProjections [[buffer(2)]]
    ) {
        uint2 outputSize = uint2(outputTexture.get_width(), outputTexture.get_height());
        if (tid.x >= outputSize.x || tid.y >= outputSize.y || tid.z >= outputTexture.get_array_size()) {
            return;
        }
        uint slice = tid.z;
        uint2 depthCoord = depthCoordinate(tid.xy, outputSize, uint2(sceneDepth.get_width(), sceneDepth.get_height()));
        float3 normal = HAS_NORMALS ? sceneNormals.read(depthCoord, slice).xyz : float3(0);
        float amount = darkness(tid.xy, outputSize, sceneDepth.read(depthCoord, slice), normal, inverseViewProjections[slice], params, shadowMapParams, shadowMapTexture, shadowMapSampler);
        if (amount > 0.0) {
            outputTexture.write(darken(outputTexture.read(tid.xy, slice), amount), tid.xy, slice);
        }
    }

}
