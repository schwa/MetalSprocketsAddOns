#pragma once

#import "MetalSprocketsAddOnsShaders.h"

typedef MS_ENUM(uint32_t, PointCloudShape) {
    PointCloudShapeSquare = 0,
    PointCloudShapeDisc = 1,
    PointCloudShapeCrosshair = 2,
    PointCloudShapeRing = 3,
};

/// The default point layout: packed world-space position and an RGBA8 colour (red in the lowest
/// byte), 16 bytes per point. Colours are written to the target as-is.
struct PointCloudPoint {
    float x;
    float y;
    float z;
    uint32_t color;
};
typedef struct PointCloudPoint PointCloudPoint;

/// What a point-description function returns for one point.
///
/// Keep in sync with `PointCloudShaderSupport.metalSource`, which runtime-compiled consumer
/// shaders use instead of this header.
struct PointCloudSplat {
    simd_float3 position;
    uint32_t color;
    /// Size in pixels. 1 or less draws a single pixel.
    float size;
    /// A `PointCloudShape` value.
    uint32_t shape;
};
typedef struct PointCloudSplat PointCloudSplat;

struct PointCloudParameters {
    simd_float4x4 viewProjection;
    simd_uint2 viewportSize;
    uint32_t pointCount;
    /// 1 when the depth buffer uses reverse Z (nearer is larger), so depth is flipped before the atomic min.
    uint32_t reverseZ;
    /// Size and shape for the default `PointCloudPoint` path.
    float pointSize;
    uint32_t pointShape;
    /// Sizes above this are clamped.
    float maximumPointSize;
};
typedef struct PointCloudParameters PointCloudParameters;
