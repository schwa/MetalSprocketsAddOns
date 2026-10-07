#pragma once

#import "MetalSprocketsAddOnsShaders.h"

typedef MS_ENUM(uint32_t, PointCloudShape) {
    PointCloudShapeSquare = 0,
    PointCloudShapeDisc = 1,
    PointCloudShapeCrosshair = 2,
    PointCloudShapeRing = 3,
};

#if defined(__METAL_VERSION__)
#define POINT_CLOUD_SWIFT_NAME(name)
#else
#define POINT_CLOUD_SWIFT_NAME(name) __attribute__((swift_name(#name)))
#endif

/// How a point's packed RGBA8 colour is encoded.
typedef MS_ENUM(uint32_t, PointCloudColorSpace) {
    /// sRGB-encoded, like most 8-bit colour data. Decoded to linear before it is written.
    PointCloudColorSpaceSRGB POINT_CLOUD_SWIFT_NAME(sRGB) = 0,
    /// Already linear.
    PointCloudColorSpaceLinear = 1,
};

/// The passes of the rasterizer. Fast mode uses one pass; blended mode uses the other two.
typedef MS_ENUM(uint32_t, PointCloudRasterPass) {
    /// Nearest point per pixel: 64-bit atomic min of (depth << 32 | colour).
    PointCloudRasterPassNearest = 0,
    /// Blended, first pass: nearest view depth per pixel.
    PointCloudRasterPassBlendedDepth = 1,
    /// Blended, second pass: sum the colours of points near that depth.
    PointCloudRasterPassBlendedAccumulate = 2,
};

/// The default point layout: packed world-space position and an RGBA8 colour (red in the lowest
/// byte), 16 bytes per point.
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
    /// A `PointCloudColorSpace` value.
    uint32_t colorSpace;
    /// A `PointCloudRasterPass` value: which pass this dispatch (or resolve) is for.
    uint32_t pass;
    /// Blended mode: points within this fraction of the nearest point's view depth are averaged.
    float depthTolerance;
};
typedef struct PointCloudParameters PointCloudParameters;
