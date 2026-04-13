#pragma once

#import "MetalSprocketsAddOnsShaders.h"

#define GRID_MAX_HIGHLIGHTED_LINES 8

/// A single highlighted grid line.
/// axis: 0 = X axis (vertical line at uv.x == position), 1 = Y axis (horizontal line at uv.y == position)
struct GridHighlightedLine {
    int axis;           // 0 = X, 1 = Y
    float position;     // grid-space position of the line
    float width;        // line width (0..1, same semantics as grid lineWidth)
    float _padding;
    simd_float4 color;  // RGBA color
};

struct GridHighlightedLines {
    int count;
    int _padding[3];
    struct GridHighlightedLine lines[GRID_MAX_HIGHLIGHTED_LINES];
};

/// Major grid subdivision. Every `interval` minor cells, draw a major line.
/// Set interval to 0 to disable.
struct GridMajorDivision {
    int interval;       // e.g. 10 = every 10th minor line is a major line
    float _padding0;
    simd_float2 lineWidth;  // major line width per axis (same semantics as grid lineWidth)
    simd_float4 color;      // RGBA color for major lines
};
