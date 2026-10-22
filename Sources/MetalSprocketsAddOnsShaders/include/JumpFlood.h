#pragma once

#import "MetalSprocketsAddOnsShaders.h"

struct JumpFloodStepParameters {
    /// Pixel offset to sample on each side, e.g. (step, 0) or (0, step).
    simd_int2 offset;
};
typedef struct JumpFloodStepParameters JumpFloodStepParameters;

struct JumpFloodOutlineParameters {
    simd_float4 color;
    /// Outline width in pixels, measured from the mask edge.
    float width;
};
typedef struct JumpFloodOutlineParameters JumpFloodOutlineParameters;
