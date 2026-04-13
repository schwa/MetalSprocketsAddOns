#pragma once

#import "MetalSprocketsAddOnsShaders.h"

#define MAX_SHADOW_LIGHTS 8

/// Parameters for a single shadow-casting light.
struct ShadowLightParameters {
    /// Light's view-projection matrix (maps world space → light clip space).
    simd_float4x4 lightViewProjectionMatrix;
};
typedef struct ShadowLightParameters ShadowLightParameters;

/// Parameters for shadow map sampling — supports multiple lights.
struct ShadowMapParameters {
    /// Per-light parameters.
    struct ShadowLightParameters lights[MAX_SHADOW_LIGHTS];
    /// Number of active shadow-casting lights.
    int lightCount;
    /// Shadow map resolution (width == height assumed square).
    float mapSize;
};
typedef struct ShadowMapParameters ShadowMapParameters;

#if defined(__METAL_VERSION__)
namespace ShadowMap {
    /// Computes shadow visibility for a world-space position across all shadow-casting lights.
    /// Returns 1.0 if fully lit, 0.0 if fully shadowed.
    float sampleShadow(
        float3 worldPosition,
        constant ShadowMapParameters &shadowParams,
        metal::depth2d_array<float, metal::access::sample> shadowMap,
        metal::sampler shadowSampler
    );
}
#endif
