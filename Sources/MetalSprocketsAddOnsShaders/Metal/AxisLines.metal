#include "MetalSprocketsAddOnsShaders.h"

using namespace metal;

namespace AxisLines {

    struct VertexOut {
        float4 position [[position]];
        float4 color;
    };

    // Generate infinite axis lines in screen space
    // Each axis uses 6 vertices (2 triangles) to create a thick line quad
    vertex VertexOut vertex_main(uint vertexID [[vertex_id]], constant AxisLinesUniforms &uniforms [[buffer(0)]]) {
        VertexOut out;

        // Determine which axis (0=X, 1=Y, 2=Z) and which vertex in the quad (0-5)
        uint axisID = vertexID / 6;
        uint quadVertexID = vertexID % 6;

        // Define axis directions in world space
        float3 axisDir;
        float4 color;

        switch (axisID) {
        case 0: // X axis
            axisDir = float3(1, 0, 0);
            color = uniforms.xAxisColor;
            break;
        case 1: // Y axis
            axisDir = float3(0, 1, 0);
            color = uniforms.yAxisColor;
            break;
        case 2: // Z axis
            axisDir = float3(0, 0, 1);
            color = uniforms.zAxisColor;
            break;
        }

        // Calculate view direction in world space
        // The view matrix transforms from world to view space, so the camera forward is the inverse Z axis
        float3 viewForward = normalize(float3(uniforms.viewMatrix[0][2], uniforms.viewMatrix[1][2], uniforms.viewMatrix[2][2]));

        // Calculate how aligned the view direction is with the axis
        // If looking directly along the axis, dot product will be close to 1
        float alignment = abs(dot(viewForward, axisDir));

        // Threshold for hiding the axis (when alignment > threshold, hide it)
        float hideThreshold = 0.999; // ~2.6 degrees

        // Make axis transparent if looking along it
        if (alignment > hideThreshold) {
            color.a = 0.0;
        }

        // Project a finite world-space segment so perspective makes it converge toward the horizon.
        float3 origin = uniforms.nudge;
        float4 clipA = uniforms.mvpMatrix * float4(origin - axisDir * uniforms.length, 1.0);
        float4 clipB = uniforms.mvpMatrix * float4(origin + axisDir * uniforms.length, 1.0);

        // Clip the segment to the part in front of the camera before dividing by w.
        const float minW = 1e-4;
        if (clipA.w < minW && clipB.w < minW) {
            out.position = float4(0, 0, 0, 1);
            out.color = float4(0);
            return out;
        }
        if (clipA.w < minW) {
            clipA = mix(clipA, clipB, (minW - clipA.w) / (clipB.w - clipA.w));
        } else if (clipB.w < minW) {
            clipB = mix(clipB, clipA, (minW - clipB.w) / (clipA.w - clipB.w));
        }

        float2 ndcA = clipA.xy / clipA.w;
        float2 ndcB = clipB.xy / clipB.w;

        // Build the quad offset in pixels so the width is the same in x and y.
        float2 deltaPixels = (ndcB - ndcA) * uniforms.viewportSize;
        if (length(deltaPixels) < 1e-6) {
            color.a = 0.0;
            deltaPixels = float2(1, 0);
        }
        float2 lineDirPixels = normalize(deltaPixels);
        float2 perpPixels = float2(-lineDirPixels.y, lineDirPixels.x);
        float2 offset = perpPixels * uniforms.lineWidth / uniforms.viewportSize;

        // 2 triangles: (A-, A+, B+), (A-, B+, B-)
        bool atB = quadVertexID == 2 || quadVertexID == 4 || quadVertexID == 5;
        float side = (quadVertexID == 1 || quadVertexID == 2 || quadVertexID == 4) ? 1.0 : -1.0;
        float4 clip = atB ? clipB : clipA;
        float2 ndc = (atB ? ndcB : ndcA) + offset * side;

        out.position = float4(ndc * clip.w, clip.z, clip.w);
        out.color = color;

        return out;
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        if (in.color.a == 0.0) {
            discard_fragment();
        }
        return in.color;
    }

} // namespace AxisLines
