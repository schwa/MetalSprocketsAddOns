#include "MetalSprocketsAddOnsShaders.h"

// https://en.wikipedia.org/wiki/Blinn–Phong_reflection_model

using namespace metal;

namespace BlinnPhong {

    struct Vertex {
        simd_float3 position ATTRIBUTE(0);
        simd_float3 normal ATTRIBUTE(1);
        simd_float2 textureCoordinate ATTRIBUTE(2);
    };

    float3 CalculateBlinnPhong(
        float3 modelPosition,
        float3 cameraPosition,
        float3 normal,
        constant LightingArgumentBuffer &lighting,
        float shininess,
        float3 ambientColor,
        float3 diffuseColor,
        float3 specularColor
    );

    // ----------------------------------------------------------------------

    // MARK: Types

    struct Fragment {
        float4 position [[position]]; // in projection space
        float3 worldPosition;
        float3 normal;
        float2 textureCoordinate;
        uint instance_id;
    };

    // MARK: Shaders

    [[vertex]] Fragment vertex_main(
        uint instance_id [[instance_id]],
        Vertex in [[stage_in]],
        constant float4x4 &modelViewMatrix [[buffer(1)]],
        constant float4x4 &modelViewProjectionMatrix [[buffer(2)]],
        constant float4x4 &modelMatrix [[buffer(3)]]
    ) {
        Fragment out;
        const float4 position = float4(in.position, 1.0);

        const float4 worldVertex = modelMatrix * position;
        out.position = modelViewProjectionMatrix * position;
        out.worldPosition = float3(worldVertex) / worldVertex.w;
        out.normal = normalize(extractNormalMatrix(modelMatrix) * in.normal);
        out.textureCoordinate = in.textureCoordinate;
        out.instance_id = instance_id;
        return out;
    }

    [[fragment]] float4 fragment_main(
        Fragment in [[stage_in]],
        constant LightingArgumentBuffer &lighting [[buffer(1)]],
        constant BlinnPhongMaterialArgumentBuffer *material [[buffer(2)]],
        constant float4x4 &cameraMatrix [[buffer(3)]]
    ) {
        uint instance_id = in.instance_id;

        float3 ambientColor = material[instance_id].ambient.resolve(in.textureCoordinate).xyz;
        float3 diffuseColor = material[instance_id].diffuse.resolve(in.textureCoordinate).xyz;
        float3 specularColor = material[instance_id].specular.resolve(in.textureCoordinate).xyz;

        auto cameraPosition = cameraMatrix.columns[3].xyz;

        float3 color = CalculateBlinnPhong(
            in.worldPosition, cameraPosition, in.normal, lighting, material[instance_id].shininess, ambientColor,
            diffuseColor, specularColor
        );
        return float4(color, 1.0);
    }

    // MARK: Helper Functions

    /// Computes the Blinn-Phong or Phong lighting model for a given surface
    /// point.
    float3 CalculateBlinnPhong(
        const float3 modelPosition,
        const float3 cameraPosition,
        const float3 normal,
        constant LightingArgumentBuffer &lighting,
        const float shininess,
        const float3 ambientColor,
        const float3 diffuseColor,
        const float3 specularColor
    ) {
        const bool phongMode = false; // Use Blinn-Phong shading by default
        float3 accumulatedDiffuseColor = float3(0.0);
        float3 accumulatedSpecularColor = float3(0.0);

        const float3 viewDirection = normalize(cameraPosition - modelPosition);

        for (int index = 0; index < lighting.lightCount; ++index) {
            const auto light = lighting.lights[index];
            const float3 lightPosition = lighting.lightPositions[index];

            float3 lightDirection = lightPosition - modelPosition;
            const float distanceSquared = length_squared(lightDirection);
            lightDirection = normalize(lightDirection);

            const float lambertian = max(dot(lightDirection, normal), 0.0);
            if (lambertian == 0.0) {
                continue;
            }

            const float attenuation = 1.0 / (1.0 + 0.09 * distanceSquared + 0.032 * distanceSquared * distanceSquared);

            float specular = 0.0;

            if (!phongMode) {
                const float3 halfDirection = normalize(lightDirection + viewDirection);
                specular = pow(max(dot(halfDirection, normal), 0.0), shininess);
            } else {
                const float3 reflectionDirection = reflect(-lightDirection, normal);
                specular = pow(max(dot(reflectionDirection, viewDirection), 0.0), shininess);
            }

            const float3 lightContribution = light.color * light.intensity * attenuation;

            accumulatedDiffuseColor += diffuseColor * lambertian * lightContribution;
            accumulatedSpecularColor += specularColor * specular * lightContribution;
        }

        return lighting.ambientLightColor * ambientColor + accumulatedDiffuseColor + accumulatedSpecularColor;
    }

} // namespace BlinnPhong
