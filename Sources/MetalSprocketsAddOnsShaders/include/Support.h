#pragma once

#import "MetalSprocketsShaders.h"

// MARK: SIMD Type aliases

typedef simd_float4x4 float4x4;
typedef simd_float3x3 float3x3;
typedef simd_float4 float4;
typedef simd_float3 float3;
typedef simd_float2 float2;

// MARK: Frame uniforms
struct FrameUniforms {
    uint index;
    float time;
    float deltaTime;
    simd_int2 viewportSize;
};
typedef struct FrameUniforms FrameUniforms;

// MARK: Math utilities

#if defined(__METAL_VERSION__)
inline float square(float x) {
    return x * x;
}

inline float3x3 extractNormalMatrix(float4x4 modelMatrix) {
    return float3x3(modelMatrix[0].xyz, modelMatrix[1].xyz, modelMatrix[2].xyz);
}
#endif

// MARK: Buffer descriptor and accessors

struct BufferDescriptor {
    uint count;        // elements in the buffer
    uint stride;       // bytes per element
    uint valueOffset;  // byte offset of the value within each element
};

#if defined(__METAL_VERSION__)
// Generic unaligned load: works for any T
template <typename T>
inline T load_at(device const uchar* base, constant BufferDescriptor& d, uint i) {
    T out;
    device const uchar* src = base + i * d.stride + d.valueOffset;
    thread uchar* dst = reinterpret_cast<thread uchar*>(&out);
    // tiny copy (no std::memcpy in MSL)
    for (uint b = 0; b < sizeof(T); ++b) { dst[b] = src[b]; }
    return out;
}

// Special-case float3 via packed_float3 to avoid alignment traps
template <>
inline float3 load_at<float3>(device const uchar* base, constant BufferDescriptor& d, uint i) {
    packed_float3 p = load_at<packed_float3>(base, d, i);
    return float3(p);
}

// Optional bounds-checked variant
template <typename T>
inline bool try_load(device const uchar* base, constant BufferDescriptor& d, uint i, thread T& out) {
    if (i >= d.count) return false;
    out = load_at<T>(base, d, i);
    return true;
}

#endif
