#pragma once

#import "MetalSprocketsShaders.h"

#ifdef __METAL_VERSION__
using namespace metal;
#else
// Make Metal-style type names available in C/Swift
typedef simd_float4x4 float4x4;
typedef simd_float4 float4;
typedef simd_float2 float2;
typedef simd_uint2 uint2;
#endif

/// Per-view constants for the Slug vertex shader.
struct SlugViewConstants {
    float4x4 viewProjectionMatrix;
    float2 viewportSize;
    float2 _padding;
};

/// Vertex data for a single glyph quad corner.
struct SlugVertexData {
    float4 posAndNorm;         // xy = object-space position, zw = outward normal
    float4 texAndAtlasOffsets; // xy = em-space coords, zw = packed glyph/band data
    float4 invJacobian;        // inverse Jacobian for object→viewport space
    float4 bandTransform;      // 2D scales and offsets for band transform
    float4 color;              // RGBA color
    uint2 indices;             // x = fontIndex, y = modelIndex
};
