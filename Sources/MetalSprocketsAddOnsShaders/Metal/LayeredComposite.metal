#include "MetalSprocketsAddOnsShaders.h"

using namespace metal;

// Copies one slice of an offscreen colour and depth array into its view's render target slice and viewport.
namespace LayeredComposite {

    struct VertexOut {
        float4 position [[position]];
        uint layer [[render_target_array_index]];
        uint viewportIndex [[viewport_array_index]];
    };

    [[vertex]] VertexOut vertex_main(uint vertexID [[vertex_id]], constant LayeredCompositeView &view [[buffer(0)]]) {
        // Oversized triangle covering the viewport.
        float2 uv = float2((vertexID << 1) & 2, vertexID & 2);
        return { float4(uv * 2.0 - 1.0, 0.0, 1.0), view.viewIndex, view.viewIndex };
    }

    struct FragmentOut {
        float4 color [[color(0)]];
        float depth [[depth(any)]];
    };

    [[fragment]] FragmentOut fragment_main(
        VertexOut in [[stage_in]],
        texture2d_array<float, access::read> color [[texture(0)]],
        depth2d_array<float, access::read> depth [[texture(1)]],
        constant LayeredCompositeView &view [[buffer(0)]]
    ) {
        float2 local = in.position.xy - view.viewportOrigin;
        uint2 size = uint2(color.get_width(), color.get_height());
        if (any(local < 0.0) || any(local >= float2(size))) {
            discard_fragment();
        }
        uint2 pixel = uint2(local);
        float sceneDepth = depth.read(pixel, view.viewIndex);
        // Pixels the scene did not draw keep whatever is behind them.
        if (sceneDepth == view.clearDepth) {
            discard_fragment();
        }
        return { color.read(pixel, view.viewIndex), sceneDepth };
    }

} // namespace LayeredComposite
