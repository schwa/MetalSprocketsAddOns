#include <metal_stdlib>

#include "MetalSprocketsAddOnsShaders.h"

using namespace metal;

// Compute rasterization of points after Schütz, Kerbl & Wimmer 2021,
// "Rendering Point Clouds with Compute Shaders and Vertex Order Optimization".
//
// Nearest mode: each point packs (depth << 32 | colour) and does a 64-bit atomic min into its
// pixel, so the nearest point wins.
//
// Blended mode (the paper's high-quality shading): a depth pass keeps the nearest view depth per
// pixel, then an accumulate pass sums the linear colours of every point within a tolerance of it.
// The resolve pass writes the average. Blended framebuffer layout, struct-of-arrays per pixel:
//   [nearest view depth (float bits)] [nearest NDC depth (float bits)] [r g b a sums] [count]
namespace PointCloud {

    // Empty pixel: larger than any packed value with a depth in [0, 1].
    constant ulong emptyPixel = 0xFFFFFFFFFFFFFFFF;

    // True when a consumer-supplied visible function describes each point.
    constant bool HAS_DESCRIBE [[function_constant(0)]];

    // Consumer hook: (point index, point buffer, user data) -> what to draw for that point.
    using DescribePoint = PointCloudSplat(uint, const device void *, const device void *);

    // Fixed-point scale for the blended colour sums.
    constant float accumulationScale = 1023.0;

    struct BlendedFramebuffer {
        device atomic_uint *nearestViewDepth;
        device atomic_uint *nearestDepth;
        device atomic_uint *sums;
        device atomic_uint *counts;

        BlendedFramebuffer(device void *base, uint pixelCount) {
            nearestViewDepth = static_cast<device atomic_uint *>(base);
            nearestDepth = nearestViewDepth + pixelCount;
            sums = nearestDepth + pixelCount;
            counts = sums + 4 * pixelCount;
        }
    };

    float4 decodeColour(uint packed, uint colorSpace) {
        return colorSpace == PointCloudColorSpaceSRGB ? unpack_unorm4x8_srgb_to_float(packed) : unpack_unorm4x8_to_float(packed);
    }

    // One covered pixel. `viewDepth` is clip.w; `depth` is NDC depth, flipped for reverse Z.
    void writePixel(device void *framebuffer, uint index, constant PointCloudParameters &params, float viewDepth, float depth, uint colour) {
        switch (params.pass) {
        case PointCloudRasterPassNearest: {
            // Non-negative floats order the same as their bit patterns.
            ulong packed = (ulong(as_type<uint>(depth)) << 32) | ulong(colour);
            atomic_min_explicit(static_cast<device atomic_ulong *>(framebuffer) + index, packed, memory_order_relaxed);
            break;
        }
        case PointCloudRasterPassBlendedDepth: {
            BlendedFramebuffer blended(framebuffer, params.viewportSize.x * params.viewportSize.y);
            atomic_fetch_min_explicit(blended.nearestViewDepth + index, as_type<uint>(viewDepth), memory_order_relaxed);
            break;
        }
        default: {
            BlendedFramebuffer blended(framebuffer, params.viewportSize.x * params.viewportSize.y);
            float nearest = as_type<float>(atomic_load_explicit(blended.nearestViewDepth + index, memory_order_relaxed));
            if (viewDepth > nearest * (1.0 + params.depthTolerance)) {
                return;
            }
            atomic_fetch_min_explicit(blended.nearestDepth + index, as_type<uint>(depth), memory_order_relaxed);
            uint4 fixed = uint4(round(decodeColour(colour, params.colorSpace) * accumulationScale));
            for (uint channel = 0; channel < 4; channel++) {
                atomic_fetch_add_explicit(blended.sums + index * 4 + channel, fixed[channel], memory_order_relaxed);
            }
            atomic_fetch_add_explicit(blended.counts + index, 1, memory_order_relaxed);
            break;
        }
        }
    }

    // Whether the pixel whose centre is `offset` pixels from the point's centre is inside the shape.
    bool covers(float2 offset, float radius, uint shape) {
        switch (shape) {
        case PointCloudShapeDisc:
            return length(offset) <= radius;
        case PointCloudShapeCrosshair:
            // One-pixel-wide lines through the centre.
            return abs(offset.x) <= 0.5 || abs(offset.y) <= 0.5;
        case PointCloudShapeRing: {
            float distance = length(offset);
            return distance <= radius && distance >= radius - max(1.0, radius * 0.25);
        }
        default:
            return true;
        }
    }

    [[kernel]] void rasterize(
        uint pointIndex [[thread_position_in_grid]],
        const device void *points [[buffer(0)]],
        device void *framebuffer [[buffer(1)]],
        constant PointCloudParameters &params [[buffer(2)]],
        visible_function_table<DescribePoint> describe [[buffer(3), function_constant(HAS_DESCRIBE)]],
        const device void *userData [[buffer(4), function_constant(HAS_DESCRIBE)]],
        device PointCloudLargeSplat *largeSplats [[buffer(5)]],
        // MTLDrawPrimitivesIndirectArguments: vertexCount, instanceCount, vertexStart, baseInstance.
        device atomic_uint *largeSplatArguments [[buffer(6)]]
    ) {
        if (pointIndex >= params.pointCount) {
            return;
        }
        PointCloudSplat splat;
        if (HAS_DESCRIBE) {
            splat = describe[0](pointIndex, points, userData);
        } else {
            PointCloudPoint point = static_cast<const device PointCloudPoint *>(points)[pointIndex];
            splat = { float3(point.x, point.y, point.z), point.color, params.pointSize, params.pointShape };
        }

        float4 clip = params.viewProjection * float4(splat.position, 1.0);
        if (clip.w <= 0.0) {
            return;
        }
        float3 ndc = clip.xyz / clip.w;
        if (ndc.z < 0.0 || ndc.z > 1.0) {
            return;
        }
        // Pixel rows run top to bottom, matching [[position]] in the resolve pass.
        float2 viewport = float2(params.viewportSize);
        float2 centre = float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5) * viewport;
        float size = params.sizeUnits == PointCloudSizeUnitsWorld ? splat.size * params.projectionScale / clip.w : splat.size;
        float depth = params.reverseZ != 0 ? 1.0 - ndc.z : ndc.z;

        // Points too large for the stamp loop go to the hardware rasterizer in the resolve pass. The
        // blended depth pass still stamps them (clamped), so blended pixels they cover stay empty
        // and the hardware draw fills them.
        if (size > params.maximumPointSize) {
            float halfSize = size * 0.5;
            if (any(centre + halfSize < 0.0) || any(centre - halfSize >= viewport)) {
                return;
            }
            if (params.pass != PointCloudRasterPassBlendedDepth && params.largeSplatCapacity > 0) {
                uint slot = atomic_fetch_add_explicit(largeSplatArguments + 1, 1, memory_order_relaxed);
                if (slot < params.largeSplatCapacity) {
                    largeSplats[slot] = { centre, depth, splat.color, size, splat.shape };
                    return;
                }
            }
            size = params.maximumPointSize;
        }

        float radius = max(size, 1.0) * 0.5;
        if (any(centre + radius < 0.0) || any(centre - radius >= viewport)) {
            return;
        }
        uint width = params.viewportSize.x;

        if (size <= 1.0) {
            if (any(centre < 0.0) || any(centre >= viewport)) {
                return;
            }
            uint2 pixel = uint2(centre);
            writePixel(framebuffer, pixel.y * width + pixel.x, params, clip.w, depth, splat.color);
            return;
        }

        // Stamp every covered pixel in the shape's bounding box, with the point's depth.
        int2 lower = max(int2(floor(centre - radius)), int2(0));
        int2 upper = min(int2(ceil(centre + radius)), int2(params.viewportSize)) - 1;
        for (int y = lower.y; y <= upper.y; y++) {
            for (int x = lower.x; x <= upper.x; x++) {
                float2 offset = float2(x, y) + 0.5 - centre;
                if (all(abs(offset) <= radius) && covers(offset, radius, splat.shape)) {
                    writePixel(framebuffer, uint(y) * width + uint(x), params, clip.w, depth, splat.color);
                }
            }
        }
    }

    struct ResolveVertexOut {
        float4 position [[position]];
    };

    struct LargeSplatVertexOut {
        float4 position [[position]];
        float2 offset;
        float radius [[flat]];
        uint shape [[flat]];
        uint color [[flat]];
    };

    // Two triangles per large splat, one instance each.
    [[vertex]] LargeSplatVertexOut large_splat_vertex(
        uint vertexID [[vertex_id]],
        uint instanceID [[instance_id]],
        const device PointCloudLargeSplat *largeSplats [[buffer(0)]],
        constant PointCloudParameters &params [[buffer(1)]]
    ) {
        LargeSplatVertexOut out;
        if (instanceID >= params.largeSplatCapacity) {
            // More points overflowed than fit; the extras were clamped in the compute pass.
            out.position = float4(0, 0, -1, 1);
            return out;
        }
        const float2 corners[6] = { {-1, -1}, {1, -1}, {1, 1}, {-1, -1}, {1, 1}, {-1, 1} };
        PointCloudLargeSplat splat = largeSplats[instanceID];
        float radius = splat.size * 0.5;
        float2 offset = corners[vertexID] * radius;
        float2 pixel = splat.centre + offset;
        float2 viewport = float2(params.viewportSize);
        float2 ndc = float2(pixel.x / viewport.x * 2.0 - 1.0, 1.0 - pixel.y / viewport.y * 2.0);
        float depth = params.reverseZ != 0 ? 1.0 - splat.depth : splat.depth;
        out.position = float4(ndc, depth, 1.0);
        out.offset = offset;
        out.radius = radius;
        out.shape = splat.shape;
        out.color = splat.color;
        return out;
    }

    [[fragment]] float4 large_splat_fragment(
        LargeSplatVertexOut in [[stage_in]],
        constant PointCloudParameters &params [[buffer(0)]]
    ) {
        if (!covers(in.offset, in.radius, in.shape)) {
            discard_fragment();
        }
        return decodeColour(in.color, params.colorSpace);
    }

    [[vertex]] ResolveVertexOut resolve_vertex(uint vertexID [[vertex_id]]) {
        // Oversized triangle covering the viewport.
        float2 uv = float2((vertexID << 1) & 2, vertexID & 2);
        return { float4(uv * 2.0 - 1.0, 0.0, 1.0) };
    }

    struct ResolveFragmentOut {
        float4 color [[color(0)]];
        float depth [[depth(any)]];
    };

    [[fragment]] ResolveFragmentOut resolve_fragment(
        ResolveVertexOut in [[stage_in]],
        device void *framebuffer [[buffer(0)]],
        constant PointCloudParameters &params [[buffer(1)]]
    ) {
        uint2 pixel = uint2(in.position.xy);
        uint index = pixel.y * params.viewportSize.x + pixel.x;
        float depth;
        float4 color;
        if (params.pass == PointCloudRasterPassNearest) {
            ulong packed = static_cast<const device ulong *>(framebuffer)[index];
            if (packed == emptyPixel) {
                discard_fragment();
            }
            depth = as_type<float>(uint(packed >> 32));
            color = decodeColour(uint(packed & 0xFFFFFFFF), params.colorSpace);
        } else {
            BlendedFramebuffer blended(framebuffer, params.viewportSize.x * params.viewportSize.y);
            uint count = atomic_load_explicit(blended.counts + index, memory_order_relaxed);
            if (count == 0) {
                discard_fragment();
            }
            uint4 sums;
            for (uint channel = 0; channel < 4; channel++) {
                sums[channel] = atomic_load_explicit(blended.sums + index * 4 + channel, memory_order_relaxed);
            }
            color = float4(sums) / (accumulationScale * float(count));
            depth = as_type<float>(atomic_load_explicit(blended.nearestDepth + index, memory_order_relaxed));
        }
        return { color, params.reverseZ != 0 ? 1.0 - depth : depth };
    }

} // namespace PointCloud
