#include <metal_stdlib>

#include "MetalSprocketsAddOnsShaders.h"

using namespace metal;

// Compute rasterization of points after Schütz, Kerbl & Wimmer 2021,
// "Rendering Point Clouds with Compute Shaders and Vertex Order Optimization".
// Each point packs (depth << 32 | colour) and does a 64-bit atomic min into its pixel,
// so the nearest point wins. A resolve pass then writes colour and depth.
namespace PointCloud {

    // Empty pixel: larger than any packed value with a depth in [0, 1].
    constant ulong emptyPixel = 0xFFFFFFFFFFFFFFFF;

    // True when a consumer-supplied visible function describes each point.
    constant bool HAS_DESCRIBE [[function_constant(0)]];

    // Consumer hook: (point index, point buffer, user data) -> what to draw for that point.
    using DescribePoint = PointCloudSplat(uint, const device void *, const device void *);

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
        device atomic_ulong *framebuffer [[buffer(1)]],
        constant PointCloudParameters &params [[buffer(2)]],
        visible_function_table<DescribePoint> describe [[buffer(3), function_constant(HAS_DESCRIBE)]],
        const device void *userData [[buffer(4), function_constant(HAS_DESCRIBE)]]
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
        float size = min(splat.size, params.maximumPointSize);
        float radius = max(size, 1.0) * 0.5;
        if (any(centre + radius < 0.0) || any(centre - radius >= viewport)) {
            return;
        }

        // Non-negative floats order the same as their bit patterns.
        float depth = params.reverseZ != 0 ? 1.0 - ndc.z : ndc.z;
        ulong packed = (ulong(as_type<uint>(depth)) << 32) | ulong(splat.color);
        uint width = params.viewportSize.x;

        if (size <= 1.0) {
            if (any(centre < 0.0) || any(centre >= viewport)) {
                return;
            }
            uint2 pixel = uint2(centre);
            atomic_min_explicit(&framebuffer[pixel.y * width + pixel.x], packed, memory_order_relaxed);
            return;
        }

        // Stamp every covered pixel in the shape's bounding box, with the point's depth.
        int2 lower = max(int2(floor(centre - radius)), int2(0));
        int2 upper = min(int2(ceil(centre + radius)), int2(params.viewportSize)) - 1;
        for (int y = lower.y; y <= upper.y; y++) {
            for (int x = lower.x; x <= upper.x; x++) {
                float2 offset = float2(x, y) + 0.5 - centre;
                if (all(abs(offset) <= radius) && covers(offset, radius, splat.shape)) {
                    atomic_min_explicit(&framebuffer[uint(y) * width + uint(x)], packed, memory_order_relaxed);
                }
            }
        }
    }

    struct ResolveVertexOut {
        float4 position [[position]];
    };

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
        const device ulong *framebuffer [[buffer(0)]],
        constant PointCloudParameters &params [[buffer(1)]]
    ) {
        uint2 pixel = uint2(in.position.xy);
        ulong packed = framebuffer[pixel.y * params.viewportSize.x + pixel.x];
        if (packed == emptyPixel) {
            discard_fragment();
        }
        float depth = as_type<float>(uint(packed >> 32));
        uint packedColor = uint(packed & 0xFFFFFFFF);
        float4 color = params.colorSpace == PointCloudColorSpaceSRGB
            ? unpack_unorm4x8_srgb_to_float(packedColor)
            : unpack_unorm4x8_to_float(packedColor);
        return { color, params.reverseZ != 0 ? 1.0 - depth : depth };
    }

} // namespace PointCloud
