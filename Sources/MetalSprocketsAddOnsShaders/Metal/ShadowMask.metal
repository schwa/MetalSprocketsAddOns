#include "MetalSprocketsAddOnsShaders.h"
#include "ShadowMap.h"

using namespace metal;

namespace ShadowMask {

    constant bool DEBUG [[function_constant(0)]];

    [[kernel]] void shadow_mask_compute(
        uint2 tid [[thread_position_in_grid]],
        depth2d<float, access::read> sceneDepth [[texture(0)]],
        depth2d_array<float, access::sample> shadowMapTexture [[texture(1)]],
        texture2d<float, access::read_write> outputTexture [[texture(2)]],
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

        float shadowFactor = ShadowMap::sampleShadow(
            worldPos.xyz,
            shadowMapParams,
            shadowMapTexture,
            shadowMapSampler
        );

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
