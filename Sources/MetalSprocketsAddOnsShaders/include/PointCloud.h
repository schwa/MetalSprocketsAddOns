#pragma once

#import "MetalSprocketsAddOnsShaders.h"

/// One point: world-space position and an RGBA8 colour (red in the lowest byte), written to the target as-is.
struct PointCloudPoint {
    simd_float3 position;
    uint32_t color;
};
typedef struct PointCloudPoint PointCloudPoint;

struct PointCloudParameters {
    simd_float4x4 viewProjection;
    simd_uint2 viewportSize;
    uint32_t pointCount;
    /// 1 when the depth buffer uses reverse Z (nearer is larger), so depth is flipped before the atomic min.
    uint32_t reverseZ;
};
typedef struct PointCloudParameters PointCloudParameters;
