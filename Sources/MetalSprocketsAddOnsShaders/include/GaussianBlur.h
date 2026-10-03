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
