#include "MetalSprocketsAddOnsShaders.h"
#include "RayTracedShadows.h"

#include <metal_stdlib>
#include <metal_raytracing>

using namespace metal;
using namespace raytracing;

namespace RayTracedShadow {

    constant bool DEBUG [[function_constant(0)]];

    [[kernel]] void shadow_compute(
        uint2 tid [[thread_position_in_grid]],
        depth2d<float, access::read> sceneDepth [[texture(0)]],
        texture2d<float, access::read_write> outputTexture [[texture(1)]],
        instance_acceleration_structure accelerationStructure [[buffer(0)]],
        constant RayTracedShadowParameters &params [[buffer(1)]]
    ) {
        uint2 outputSize = uint2(outputTexture.get_width(), outputTexture.get_height());

        // Bounds check
        if (tid.x >= outputSize.x || tid.y >= outputSize.y) {
            return;
        }

        // Map thread position to depth texture coordinates (may differ in size)
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

        float3 origin = worldPos.xyz;

        // Scale self-intersection bias by camera distance
        float cameraDist = length(origin);
        float bias = max(0.01, cameraDist * 0.002);

        // Create intersector — we only need to know if *any* intersection exists
        intersector<triangle_data, instancing> i;
        i.accept_any_intersection(true); // Early out on first hit

        // Test visibility for each light, weighted by attenuation.
        // Accumulate the fraction of light that is blocked.
        int lightCount = params.lighting.lightCount;
        float totalContribution = 0.0;
        float blockedContribution = 0.0;

        for (int lightIndex = 0; lightIndex < lightCount; lightIndex++) {
            float3 lightPos = params.lighting.lightPositions[lightIndex];
            float3 toLight = lightPos - origin;
            float distanceToLight = length(toLight);
            float3 direction = toLight / distanceToLight;

            // Inverse-square attenuation (matching Blinn-Phong)
            auto light = params.lighting.lights[lightIndex];
            float attenuation = light.intensity / (distanceToLight * distanceToLight + 1.0);
            totalContribution += attenuation;

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
            return; // Fully lit or no lights — no modification needed
        }

        // Shadow factor weighted by light contribution
        float shadowFactor = blockedContribution / totalContribution;

        // Darken the existing pixel
        float4 existing = outputTexture.read(tid);

        if (DEBUG) {
            float3 debugColor = float3(1.0, 0.0, 1.0);
            existing.rgb = mix(existing.rgb, debugColor, params.shadowIntensity * shadowFactor);
        } else {
            existing.rgb *= 1.0 - (params.shadowIntensity * shadowFactor);
        }

        outputTexture.write(existing, tid);
    }

} // namespace RayTracedShadow
