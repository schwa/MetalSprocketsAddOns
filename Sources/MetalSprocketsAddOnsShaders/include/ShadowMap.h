#pragma once

#import "MetalSprocketsAddOnsShaders.h"

/// Parameters for shadow map sampling in lit fragment shaders.
struct ShadowMapParameters {
    /// Light's view-projection matrix (maps world space → light clip space).
    simd_float4x4 lightViewProjectionMatrix;
    /// Shadow bias to prevent acne artifacts.
    float bias;
    /// Shadow map resolution (width == height assumed square).
    float mapSize;
};
typedef struct ShadowMapParameters ShadowMapParameters;

#if defined(__METAL_VERSION__)
namespace ShadowMap {
    /// Computes shadow visibility for a world-space position.
    /// Returns 1.0 if fully lit, 0.0 if fully shadowed.
    float sampleShadow(
        float3 worldPosition,
        constant ShadowMapParameters &shadowParams,
        metal::depth2d<float, metal::access::sample> shadowMap,
        metal::sampler shadowSampler
    );
}
#endif
