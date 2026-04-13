#pragma once

#import "MetalSprocketsAddOnsShaders.h"
#import "Lighting.h"

/// Parameters for the ray-traced shadow mask pass.
struct RayTracedShadowParameters {
    /// Inverse of the camera's view-projection matrix (to reconstruct world position from depth).
    simd_float4x4 inverseViewProjection;
    /// Lighting argument buffer (contains light positions and count).
    LightingArgumentBuffer lighting;
    /// Maximum ray distance for shadow testing (0 = unlimited).
    float maxRayDistance;
    /// Shadow darkness multiplier (0 = no shadow, 1 = fully dark).
    float shadowIntensity;
};
typedef struct RayTracedShadowParameters RayTracedShadowParameters;
