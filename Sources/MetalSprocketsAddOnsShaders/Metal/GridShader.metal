#include "MetalSprocketsAddOnsShaders.h"
#include "GridShader.h"

using namespace metal;

namespace GridShader {

    // Vertex Input
    struct VertexInput {
        float3 position [[attribute(0)]];
        float2 uv [[attribute(1)]];
    };

    // Vertex Output
    struct VertexOutput {
        float4 position [[position]];
        float2 uv;
    };

    // Vertex Shader
    vertex VertexOutput vertex_main(
        VertexInput in [[stage_in]],
        constant float4x4 &modelViewProjectionMatrix [[buffer(2)]]
    ) {
        VertexOutput out;
        out.position = modelViewProjectionMatrix * float4(in.position, 1.0);
        out.uv = in.uv;
        return out;
    }

    // "Pristine Grid" from Ben Golus
    // https://bgolus.medium.com/the-best-darn-grid-shader-yet-727f9278b9d8
    float pristineGrid(float2 uv, float2 lineWidth) {
        lineWidth = saturate(lineWidth);

        float4 uvDDXY = float4(dfdx(uv), dfdy(uv));
        float2 uvDeriv = float2(length(uvDDXY.xz), length(uvDDXY.yw));

        bool2 invertLine = lineWidth > 0.5;
        float2 targetWidth = select(lineWidth, 1.0 - lineWidth, invertLine);

        float2 drawWidth = clamp(targetWidth, uvDeriv, 0.5);
        float2 lineAA = max(uvDeriv, 0.000001) * 1.5;

        float2 gridUV = abs(fract(uv) * 2.0 - 1.0);
        gridUV = select(1.0 - gridUV, gridUV, invertLine);

        float2 grid2 = smoothstep(drawWidth + lineAA, drawWidth - lineAA, gridUV);
        grid2 *= saturate(targetWidth / drawWidth);
        grid2 = mix(grid2, targetWidth, saturate(uvDeriv * 2.0 - 1.0));
        grid2 = select(grid2, 1.0 - grid2, invertLine);

        return mix(grid2.x, 1.0, grid2.y);
    }

    // Pristine single-axis line at a specific position.
    // Same anti-aliasing approach as pristineGrid but for one non-repeating line.
    float pristineLine(float uv, float position, float lineWidth, float uvDeriv) {
        lineWidth = saturate(lineWidth);

        float drawWidth = max(lineWidth, uvDeriv);
        float lineAA = max(uvDeriv, 0.000001) * 1.5;

        float dist = abs(uv - position) * 2.0;

        float line = smoothstep(drawWidth + lineAA, drawWidth - lineAA, dist);
        line *= saturate(lineWidth / drawWidth);

        return line;
    }

    // Fragment Shader
    fragment float4 fragment_main(
        VertexOutput in [[stage_in]],
        constant float2 &gridScale [[buffer(1)]],
        constant float2 &lineWidth [[buffer(2)]],
        constant float4 &gridColor [[buffer(3)]],
        constant float4 &backgroundColor [[buffer(4)]],
        constant GridHighlightedLines &highlightedLines [[buffer(5)]],
        constant GridMajorDivision &majorDivision [[buffer(6)]],
        constant float4 &backfaceColor [[buffer(7)]],
        bool front_facing [[front_facing]]
    ) {
        // If backfaceColor alpha > 0 and this is a back face, return the backface color
        if (!front_facing && backfaceColor.a > 0.0) {
            return backfaceColor;
        }
        float2 scaledUV = in.uv / gridScale;

        // Minor grid
        float grid = pristineGrid(scaledUV, lineWidth);
        float4 color = mix(backgroundColor, gridColor, grid);

        // Major grid subdivision
        if (majorDivision.interval > 0) {
            float divisor = float(majorDivision.interval);
            float2 majorUV = scaledUV / divisor;
            float majorGrid = pristineGrid(majorUV, majorDivision.lineWidth);
            float majorAlpha = majorGrid * majorDivision.color.a;
            color = mix(color, float4(majorDivision.color.rgb, 1.0), majorAlpha);
        }

        // Derivative lengths for highlighted lines
        float4 uvDDXY = float4(dfdx(scaledUV), dfdy(scaledUV));
        float2 uvDeriv = float2(length(uvDDXY.xz), length(uvDDXY.yw));

        // Blend highlighted lines on top
        int count = min(highlightedLines.count, GRID_MAX_HIGHLIGHTED_LINES);
        for (int i = 0; i < count; i++) {
            constant auto &hl = highlightedLines.lines[i];

            float coverage;
            if (hl.axis == 0) {
                coverage = pristineLine(scaledUV.x, hl.position, hl.width, uvDeriv.x);
            } else {
                coverage = pristineLine(scaledUV.y, hl.position, hl.width, uvDeriv.y);
            }

            float alpha = coverage * hl.color.a;
            color = mix(color, float4(hl.color.rgb, 1.0), alpha);
        }

        return color;
    }

} // namespace GridShader
