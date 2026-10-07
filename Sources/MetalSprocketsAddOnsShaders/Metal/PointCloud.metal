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

    [[kernel]] void rasterize(
        uint pointIndex [[thread_position_in_grid]],
        const device PointCloudPoint *points [[buffer(0)]],
        device atomic_ulong *framebuffer [[buffer(1)]],
        constant PointCloudParameters &params [[buffer(2)]]
    ) {
        if (pointIndex >= params.pointCount) {
            return;
        }
        PointCloudPoint point = points[pointIndex];
        float4 clip = params.viewProjection * float4(point.position, 1.0);
        if (clip.w <= 0.0) {
            return;
        }
        float3 ndc = clip.xyz / clip.w;
        if (any(abs(ndc.xy) > 1.0) || ndc.z < 0.0 || ndc.z > 1.0) {
            return;
        }
        // Pixel rows run top to bottom, matching [[position]] in the resolve pass.
        float2 viewport = float2(params.viewportSize);
        uint2 pixel = uint2(float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5) * viewport);
        pixel = min(pixel, params.viewportSize - 1);

        // Non-negative floats order the same as their bit patterns.
        float depth = params.reverseZ != 0 ? 1.0 - ndc.z : ndc.z;
        ulong packed = (ulong(as_type<uint>(depth)) << 32) | ulong(point.color);
        atomic_min_explicit(&framebuffer[pixel.y * params.viewportSize.x + pixel.x], packed, memory_order_relaxed);
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
        float4 color = unpack_unorm4x8_to_float(uint(packed & 0xFFFFFFFF));
        return { color, params.reverseZ != 0 ? 1.0 - depth : depth };
    }

} // namespace PointCloud
