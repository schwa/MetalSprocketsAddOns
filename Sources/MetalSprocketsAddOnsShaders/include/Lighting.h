#pragma once

#import "MetalSprocketsAddOnsShaders.h"

typedef MS_ENUM(int, LightType){
    kLightTypeDirectional = 0,
    kLightTypePoint = 1,
    kLightTypeSpot = 2,
};

struct Light {
    LightType type;
    simd_float3 color;
    float intensity;
    float range;
    // Spot cone half-angles in radians. Full intensity inside inner, zero outside outer.
    float innerConeAngle;
    float outerConeAngle;
};
typedef struct Light Light;

struct LightingArgumentBuffer {
    simd_float3 ambientLightColor;
    int lightCount;
    BUFFER(constant, Light *) lights;
    BUFFER(constant, simd_float3 *) lightPositions;
    // Direction the light points (travels), world space. Used by directional and spot lights.
    BUFFER(constant, simd_float3 *) lightDirections;
};
typedef struct LightingArgumentBuffer LightingArgumentBuffer;
