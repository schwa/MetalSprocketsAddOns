# RFC 002: Shadow Techniques

## Summary

MetalSprocketsAddOns provides two shadow techniques: shadow mapping and ray-traced shadows. Both reconstruct world positions from the scene depth buffer and composite shadows as a post-process darkening pass over the already-rendered scene.

## Technique 1: Shadow Mapping

Classic two-pass shadow mapping with support for multiple lights.

### How it works

1. **Depth pass** (`ShadowMapDepthPass`): Renders scene geometry from each light's point of view into a `depth2d_array` texture (one slice per light). Uses an orthographic projection suited to directional lights.
2. **Mask pass** (`ShadowMaskPass`): A fullscreen fragment shader reconstructs world position from the scene depth buffer, transforms it into each light's clip space, and samples the shadow map with a comparison sampler (hardware PCF). Outputs shadow darkness via alpha blending to darken the scene.

### Key components

- `ShadowMap` — owns the depth array texture, comparison sampler, per-light view-projection matrices, and bias parameters. Supports inverse-Z for better depth precision.
- `ShadowMapDepthPass` — declarative element that renders shadow caster geometry into the depth texture, one render pass per light slice.
- `ShadowMaskPass` — fullscreen post-process element that reads scene depth + shadow map and blends shadow darkness onto the scene.

### Configuration

- Resolution (default 2048), light count, depth bias, slope-scale bias, inverse-Z toggle.
- Per-light directional parameters: position, target, ortho size, near/far.

### Tradeoffs

- **Pro:** Works on all Metal hardware. Predictable performance. Well-understood technique.
- **Con:** Resolution-dependent aliasing (blocky shadow edges). Requires bias tuning to avoid shadow acne and peter-panning. Orthographic projection only (directional lights). Additional geometry passes scale linearly with light count.

## Technique 2: Ray-Traced Shadows

Hardware-accelerated ray tracing for pixel-accurate shadows.

### How it works

1. **Acceleration structure build** (`AccelerationStructureManager`): Builds a two-level acceleration structure — primitive (per-mesh triangle geometry) and instance (scene layout with transforms). Supports incremental instance updates when only transforms change.
2. **Shadow compute pass** (`RayTracedShadowComputePass`): A compute shader reconstructs world position from the scene depth buffer, then casts a shadow ray toward each light using Metal's ray tracing intersection API. If the ray hits geometry before reaching the light, the pixel is shadowed. Directly darkens pixels in the output texture.

### Key components

- `AccelerationStructureManager` — builds and caches primitive and instance acceleration structures from `MTKMesh` data. Provides `updateInstances()` for transform-only refits.
- `RayTracedShadowComputePass` — compute-based element that dispatches threads per pixel, reads depth, casts rays, and writes shadow results. Uses `Lighting` argument buffers for light positions.

### Configuration

- Max ray distance (0 = distance to light), shadow intensity (0–1), debug overlay toggle.

### Tradeoffs

- **Pro:** Pixel-perfect shadow boundaries — no aliasing, no bias tuning. Works with any light type (the ray direction comes from the light position). No additional geometry passes regardless of light count. Handles complex occluders (self-shadowing, thin geometry) naturally.
- **Con:** Requires Metal ray tracing hardware (Apple Silicon). Acceleration structures have build cost (amortized if geometry is static). Performance scales with ray count (pixels × lights). Hard shadows only — soft penumbra requires additional work (e.g., multiple jittered rays).

## Shared Design Decisions

- Both techniques operate as post-process passes over an already-rendered scene, reading the scene depth buffer. The main scene render doesn't need to know about shadows.
- Both support a debug mode that overlays magenta on shadowed pixels.
- Both use `ShaderLibrary.module` with namespaced shader functions.

## Open Questions

- Soft shadows for the ray-traced path (stochastic sampling, denoising).
- Point/spot light shadow maps (cube maps or dual paraboloid).
- Cascaded shadow maps for large outdoor scenes.
- Shadow map caching for static lights.
