#include "MetalSprocketsAddOnsShaders.h"

using namespace metal;

namespace FlatShader {

    // Function constant to enable/disable vertex colors
    // Defaults to false for backwards compatibility
    constant bool USE_VERTEX_COLORS [[function_constant(0)]];

    struct VertexIn {
        float3 position [[attribute(0)]];
        float3 normal [[attribute(1)]];
        float2 textureCoordinate [[attribute(2)]];
        // Optional vertex color - only used when USE_VERTEX_COLORS is true
        float4 color [[attribute(3)]];
    };

    struct VertexOut {
        float4 position [[position]];
        float2 textureCoordinate;
        float4 color;  // Always pass through, but only used when USE_VERTEX_COLORS is true
    };

    [[vertex]] VertexOut vertex_main(
        uint instance_id [[instance_id]],
        const VertexIn in [[stage_in]],
        constant float4x4 &modelViewProjection [[buffer(1)]]
    ) {
        VertexOut out;
        float4 objectSpace = float4(in.position, 1.0);
        out.position = modelViewProjection * objectSpace;
        out.textureCoordinate = in.textureCoordinate;

        // Pass through vertex color (will be optimized out if not used)
        if (USE_VERTEX_COLORS) {
            out.color = in.color;
        } else {
            out.color = float4(1.0);  // White/no-op multiplier
        }

        return out;
    }

    [[fragment]] float4
    fragment_main(VertexOut in [[stage_in]], constant ColorSourceArgumentBuffer &specifier [[buffer(0)]]) {
        float4 baseColor = specifier.resolve(in.textureCoordinate);

        // Multiply by vertex color if enabled
        if (USE_VERTEX_COLORS) {
            return baseColor * in.color;
        } else {
            return baseColor;
        }
    }

} // namespace FlatShader
