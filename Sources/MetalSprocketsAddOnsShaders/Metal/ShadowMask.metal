#include "MetalSprocketsAddOnsShaders.h"
#include "ShadowMap.h"

using namespace metal;

namespace ShadowMask {

    constant bool DEBUG [[function_constant(0)]];

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
    };

    // Fullscreen triangle — 3 vertices, no vertex buffer needed
    [[vertex]] VertexOut vertex_main(uint vertexID [[vertex_id]]) {
        float2 positions[] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
        float2 texCoords[] = { float2(0, 1), float2(2, 1), float2(0, -1) };
        VertexOut out;
        out.position = float4(positions[vertexID], 0, 1);
        out.texCoord = texCoords[vertexID];
        return out;
    }

    [[fragment]] float4 fragment_main(
        VertexOut in [[stage_in]],
        depth2d<float, access::sample> sceneDepth [[texture(0)]],
        depth2d<float, access::sample> shadowMapTexture [[texture(1)]],
        sampler shadowMapSampler [[sampler(0)]],
        constant float4x4 &inverseViewProjection [[buffer(0)]],
        constant ShadowMapParameters &shadowMapParams [[buffer(1)]]
    ) {
        // Sample scene depth
        constexpr sampler depthSampler(filter::nearest);
        float depth = sceneDepth.sample(depthSampler, in.texCoord);

        // Skip background (depth at clear value — 0.0 for inverse Z, 1.0 for standard)
        if (depth == 0.0 || depth == 1.0) {
            return float4(0, 0, 0, 0); // no shadow on background
        }

        // Reconstruct world position from screen UV + depth
        float2 ndc = in.texCoord * 2.0 - 1.0;
        ndc.y = -ndc.y; // flip Y for Metal NDC
        float4 clipPos = float4(ndc, depth, 1.0);
        float4 worldPos = inverseViewProjection * clipPos;
        worldPos /= worldPos.w;

        // Sample shadow map
        float shadowFactor = ShadowMap::sampleShadow(
            worldPos.xyz,
            shadowMapParams,
            shadowMapTexture,
            shadowMapSampler
        );

        // Debug: magenta for shadowed areas over the scene
        if (DEBUG) {
            if (shadowFactor >= 1.0) {
                return float4(0, 0, 0, 0); // fully lit — no overlay
            }
            return float4(1.0, 0.0, 1.0, 1.0 - shadowFactor);
        }

        // Output: alpha = shadow darkness (1 = fully shadowed, 0 = fully lit)
        return float4(0, 0, 0, 1.0 - shadowFactor);
    }

}
