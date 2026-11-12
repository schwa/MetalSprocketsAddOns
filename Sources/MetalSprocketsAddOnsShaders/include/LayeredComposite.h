#pragma once

#import "MetalSprocketsAddOnsShaders.h"

/// Which view of a multi-view pass a layered composite draws into.
struct LayeredCompositeView {
    /// The view's viewport origin in render target pixels.
    simd_float2 viewportOrigin;
    /// Source array slice, render target array slice and viewport index.
    uint32_t viewIndex;
    /// The depth the source was cleared to; those pixels are not drawn.
    float clearDepth;
};
typedef struct LayeredCompositeView LayeredCompositeView;
