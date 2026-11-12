#include <metal_stdlib>
#include <metal_raytracing>

#include "MetalSprocketsAddOnsShaders.h"
#include "RayTracedShadows.h"

using namespace metal;
using namespace raytracing;

namespace RayTracedShadow {

    constant bool DEBUG [[function_constant(0)]];
    // True when a world-space shading normal texture is bound.
    constant bool HAS_NORMALS [[function_constant(1)]];

    // Map thread position to depth texture coordinates (may differ in size)
    uint2 depthCoordinate(uint2 tid, uint2 outputSize, uint2 depthSize) {
        return uint2(
            uint(float(tid.x) * float(depthSize.x) / float(outputSize.x)),
            uint(float(tid.y) * float(depthSize.y) / float(outputSize.y))
        );
    }

    // The fraction of light blocked at one pixel (0 = fully lit). `storedNormal` is zero when there is none.
    float shadowFactor(
        uint2 tid,
        uint2 outputSize,
        float depth,
        float3 storedNormal,
        float4x4 inverseViewProjection,
        metal::raytracing::instance_acceleration_structure accelerationStructure,
        constant RayTracedShadowParameters &params
    ) {
        // Skip background (depth at clear value — 0.0 for inverse Z, 1.0 for standard)
        if (depth == 0.0 || depth == 1.0) {
            return 0.0;
        }

        // Reconstruct world position from screen UV + depth
        float2 texCoord = (float2(tid) + 0.5) / float2(outputSize);
        float2 ndc = texCoord * 2.0 - 1.0;
        ndc.y = -ndc.y; // flip Y for Metal NDC
        float4 clipPos = float4(ndc, depth, 1.0);
        float4 worldPos = inverseViewProjection * clipPos;
        worldPos /= worldPos.w;

        float3 origin = worldPos.xyz;

        // Scale self-intersection bias by camera distance
        float cameraDist = length(origin);
        float bias = max(0.01, cameraDist * 0.002);

        // With a smooth shading normal, surfaces facing away from a light are shadowed from it without tracing, and
        // rays start off the surface along the normal, so the mesh's flat triangles do not shadow themselves.
        float3 normal = 0;
        if (length_squared(storedNormal) > 0.25) {
            normal = normalize(storedNormal);
            origin += normal * bias;
        }
        const bool hasNormal = any(normal != 0);

        // Create intersector — we only need to know if *any* intersection exists
        intersector<triangle_data, instancing> i;
        i.accept_any_intersection(true); // Early out on first hit

        // Test visibility for each light, weighted by attenuation.
        // Accumulate the fraction of light that is blocked.
        int lightCount = params.lighting.lightCount;
        float totalContribution = 0.0;
        float blockedContribution = 0.0;

        for (int lightIndex = 0; lightIndex < lightCount; lightIndex++) {
            auto light = params.lighting.lights[lightIndex];
            float3 lightPointing = params.lighting.lightDirections[lightIndex];

            float3 direction;
            float distanceToLight;
            float attenuation;
            if (light.type == kLightTypeDirectional) {
                direction = -lightPointing;
                distanceToLight = INFINITY;
                attenuation = light.intensity;
            } else {
                float3 toLight = params.lighting.lightPositions[lightIndex] - origin;
                distanceToLight = length(toLight);
                direction = toLight / distanceToLight;
                // Inverse-square attenuation (matching Blinn-Phong)
                attenuation = light.intensity / (distanceToLight * distanceToLight + 1.0);
                if (light.type == kLightTypeSpot) {
                    attenuation *= smoothstep(cos(light.outerConeAngle), cos(light.innerConeAngle), dot(-direction, lightPointing));
                }
            }
            if (attenuation <= 0.0) {
                continue;
            }
            totalContribution += attenuation;
            if (hasNormal && dot(normal, direction) <= 0.0) {
                blockedContribution += attenuation;
                continue;
            }

            float maxDistance = params.maxRayDistance > 0.0 ? min(params.maxRayDistance, distanceToLight) : distanceToLight;

            ray shadowRay;
            shadowRay.origin = origin;
            shadowRay.direction = direction;
            shadowRay.min_distance = bias;
            shadowRay.max_distance = maxDistance;

            auto result = i.intersect(shadowRay, accelerationStructure);

            if (result.type != intersection_type::none) {
                blockedContribution += attenuation;
            }
        }

        if (lightCount <= 0 || totalContribution <= 0.0 || blockedContribution <= 0.0) {
            return 0.0; // Fully lit or no lights — no modification needed
        }

        // Shadow factor weighted by light contribution
        return blockedContribution / totalContribution;
    }

    float4 darken(float4 existing, float shadowFactor, float shadowIntensity) {
        if (DEBUG) {
            existing.rgb = mix(existing.rgb, float3(1.0, 0.0, 1.0), shadowIntensity * shadowFactor);
        } else {
            existing.rgb *= 1.0 - (shadowIntensity * shadowFactor);
        }
        return existing;
    }

    [[kernel]] void shadow_compute(
        uint2 tid [[thread_position_in_grid]],
        depth2d<float, access::read> sceneDepth [[texture(0)]],
        texture2d<float, access::read_write> outputTexture [[texture(1)]],
        texture2d<float, access::read> sceneNormals [[texture(2), function_constant(HAS_NORMALS)]],
        metal::raytracing::instance_acceleration_structure accelerationStructure [[buffer(0)]],
        constant RayTracedShadowParameters &params [[buffer(1)]]
    ) {
        uint2 outputSize = uint2(outputTexture.get_width(), outputTexture.get_height());
        if (tid.x >= outputSize.x || tid.y >= outputSize.y) {
            return;
        }
        uint2 depthCoord = depthCoordinate(tid, outputSize, uint2(sceneDepth.get_width(), sceneDepth.get_height()));
        float3 normal = HAS_NORMALS ? sceneNormals.read(depthCoord).xyz : float3(0);
        float factor = shadowFactor(tid, outputSize, sceneDepth.read(depthCoord), normal, params.inverseViewProjection, accelerationStructure, params);
        if (factor > 0.0) {
            outputTexture.write(darken(outputTexture.read(tid), factor, params.shadowIntensity), tid);
        }
    }

    // One view per array slice (for example both eyes of a visionOS immersive space); the grid's z is the slice.
    [[kernel]] void shadow_compute_layered(
        uint3 tid [[thread_position_in_grid]],
        depth2d_array<float, access::read> sceneDepth [[texture(0)]],
        texture2d_array<float, access::read_write> outputTexture [[texture(1)]],
        texture2d_array<float, access::read> sceneNormals [[texture(2), function_constant(HAS_NORMALS)]],
        metal::raytracing::instance_acceleration_structure accelerationStructure [[buffer(0)]],
        constant RayTracedShadowParameters &params [[buffer(1)]],
        constant float4x4 *inverseViewProjections [[buffer(2)]]
    ) {
        uint2 outputSize = uint2(outputTexture.get_width(), outputTexture.get_height());
        if (tid.x >= outputSize.x || tid.y >= outputSize.y || tid.z >= outputTexture.get_array_size()) {
            return;
        }
        uint slice = tid.z;
        uint2 depthCoord = depthCoordinate(tid.xy, outputSize, uint2(sceneDepth.get_width(), sceneDepth.get_height()));
        float3 normal = HAS_NORMALS ? sceneNormals.read(depthCoord, slice).xyz : float3(0);
        float factor = shadowFactor(tid.xy, outputSize, sceneDepth.read(depthCoord, slice), normal, inverseViewProjections[slice], accelerationStructure, params);
        if (factor > 0.0) {
            outputTexture.write(darken(outputTexture.read(tid.xy, slice), factor, params.shadowIntensity), tid.xy, slice);
        }
    }

} // namespace RayTracedShadow
