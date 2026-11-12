#pragma once

#import "MetalSprocketsAddOnsShaders.h"

struct GaussianBlurParameters {
    /// (1, 0) for the horizontal pass, (0, 1) for the vertical pass.
    simd_int2 direction;
    /// Number of taps on each side of the centre tap.
    int radius;
    /// 0 = clamp to edge, 1 = treat samples outside the texture as zero.
    int edgeMode;
};
typedef struct GaussianBlurParameters GaussianBlurParameters;

struct FastBlurDownsampleParameters {
    /// (1, 0) to shrink along X, (0, 1) to shrink along Y.
    simd_int2 direction;
    /// Source pixels averaged into one output pixel.
    int factor;
};
typedef struct FastBlurDownsampleParameters FastBlurDownsampleParameters;

struct FastBlurUpsampleParameters {
    /// Full-resolution pixels per low-resolution pixel, per axis.
    simd_int2 factor;
    /// Per axis: 1 = cubic B-spline reconstruction, 0 = bilinear.
    simd_int2 bSpline;
};
typedef struct FastBlurUpsampleParameters FastBlurUpsampleParameters;
