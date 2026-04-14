# ISSUES.md

---

## 1: Replace histogram image comparison with GoldenImage package
status: new
priority: medium
kind: none
created: 2026-01-17T00:00:00Z

The test Support.swift uses a homebrew histogram-based image comparison (vImage, CoreImage, Histogram struct). Replace this with the GoldenImage package which provides PSNR-based comparison. Requires publishing GoldenImage to GitHub first, then adding it as a dependency.

---

## 2: Remove local cross-environment macros and adopt them from MetalSprockets
status: closed
priority: medium
kind: task
created: 2026-04-02T18:30:29Z
updated: 2026-04-02T18:43:48Z
closed: 2026-04-02T18:43:48Z

Once MetalSprockets#305 is complete, remove the locally defined cross-environment macros from `Sources/MetalSprocketsAddOnsShaders/include/Support.h` (TEXTURE2D, DEPTH2D, TEXTURECUBE, SAMPLER, BUFFER, ATTRIBUTE, MS_ENUM) and import them from MetalSprockets instead.

Blocked on MetalSprockets#305.

---

## 3: Demo views render with wrong size/aspect ratio on initial load
status: closed
priority: medium
kind: bug
created: 2026-04-13T05:04:24Z
updated: 2026-04-14T02:52:38Z
closed: 2026-04-14T02:52:38Z

RenderView-based demos (Spinning Cube, GraphicsContext3D) render with incorrect aspect ratio or empty content on first load. Requires window resize or navigating away and back to fix. Likely caused by RenderView receiving a stale/zero drawable size before the NavigationSplitView detail column finishes layout. May be a DemoKit or MetalSprockets RenderView issue.

---

## 4: GraphicsContext3D fill renders as white instead of specified color
status: new
priority: medium
kind: bug
created: 2026-04-13T05:07:02Z
updated: 2026-04-13T05:10:47Z

Fill geometry in GraphicsContext3D renders as white when using fractional alpha (e.g. opacity 0.3). With full opacity the color is correct. The fill render pipeline has no blending enabled — alpha values are written to the framebuffer but don't affect compositing, resulting in near-white output for low-alpha fills. Need to enable alpha blending via renderPipelineDescriptorModifier on the fill pipeline.

---

## 5: GraphicsContext3D fill projection hardcoded to XY plane — fails for XZ/YZ geometry
status: new
priority: medium
kind: bug
created: 2026-04-13T05:08:59Z

generateFillGeometry() projects 3D points onto XY (drops Z) for earcut triangulation. This produces degenerate geometry for paths on the XZ or YZ planes (e.g. the star on the ground plane at y=0 — all points project to a line). Should detect the dominant plane or use the path's normal to choose the projection axis.

---

## 6: Integrate Slug text rendering into GraphicsContext3D
status: new
priority: low
kind: feature
created: 2026-04-13T05:26:59Z

Add a text drawing API to GraphicsContext3D (e.g. ctx.text("label", at: position, font:, color:)) that uses Slug for GPU-rendered text. Would allow placing text labels in 3D scenes without manually managing SlugScene/SlugTextMeshBuilder alongside the graphics context.

---

## 7: GraphicsContext3D does not render until window is resized
status: closed
priority: high
kind: bug
created: 2026-04-13T17:21:37Z
updated: 2026-04-14T02:52:38Z
closed: 2026-04-14T02:52:38Z

GraphicsContext3D content is completely invisible on initial load. Requires a window resize to trigger rendering. Affects both the standalone GraphicsContext3D demo and the BlinnPhong demo light marker. Possibly related to #3 (wrong size/aspect on initial load) but this is a complete rendering failure, not just wrong aspect.

---

## 8: Shadow map (rasterization-based) shadows
status: closed
priority: medium
kind: feature
created: 2026-04-13T17:48:11Z
updated: 2026-04-13T19:44:23Z
closed: 2026-04-13T19:44:23Z

Add shadow mapping support using a traditional rasterization approach. Render depth from the light's POV into a shadow map texture, then sample it in the fragment shader to determine shadow visibility. This avoids ray tracing entirely and can reuse existing pipeline patterns. Integrates with the existing Lighting and BlinnPhong infrastructure.

- `2026-04-13T19:44:23Z`: Basic shadow mapping working: depth pass renders from light POV, PCF sampling in Blinn-Phong shader, debug visualization toggle. Remaining issues tracked in #10, #11, #12, #13.

---

## 9: Ray traced shadows
status: closed
priority: medium
kind: feature
created: 2026-04-13T17:48:18Z
updated: 2026-04-13T23:03:52Z
closed: 2026-04-13T23:03:52Z

Add ray traced shadow support using Metal ray tracing APIs. Build MTLPrimitiveAccelerationStructure from meshes and MTLInstanceAccelerationStructure for the scene. Cast shadow rays in the fragment shader against the acceleration structure to determine visibility. Provides higher quality shadows than shadow maps (no aliasing, no acne, correct for all geometry). Requires new MetalSprockets Element wrappers for acceleration structure management and resource binding.

### Architecture

The feature follows the same pattern as the existing shadow map implementation (depth pass → scene pass → shadow mask overlay), but replaces the shadow map with ray tracing for the visibility test.

**Two public types:**

1. **AccelerationStructureManager** — CPU-side builder that owns the Metal acceleration structures
2. **RayTracedShadowMaskPass** — MetalSprockets Element that does the actual shadow rendering

### How it works

**Build phase (once, or when geometry changes):**
- Takes an array of MTKMesh and an array of Instance (mesh index + transform)
- Builds one MTLPrimitiveAccelerationStructure per unique mesh from its vertex/index buffers
- Combines them into a single MTLInstanceAccelerationStructure with per-instance transforms
- This is done synchronously on a dedicated command queue (separate from rendering)

**Render phase (every frame):**
1. Scene renders normally with Blinn-Phong lighting (no shadow awareness needed)
2. Depth attachment is stored
3. RayTracedShadowMaskPass runs as a fullscreen triangle post-process:
   - Reads scene depth texture
   - Reconstructs world position from depth + inverse view-projection matrix
   - Casts a ray from the surface point toward the light
   - Uses intersector with accept_any_intersection(true) for early-out (we only need hit/miss, not closest hit)
   - Outputs black with alpha = shadow darkness, blended multiplicatively over the scene

### Key design decisions

- **Post-process approach** (same as ShadowMaskPass) rather than per-material shadow sampling. This means any shader can receive shadows without modification — you just add the pass after your scene render.
- **accept_any_intersection(true)** — since we only care whether something blocks the light, not what, the intersector can bail on the first hit. Much faster than finding the closest intersection.
- **Ray biased along direction** — a small constant bias (0.001) along the ray direction prevents self-intersection artifacts (the ray tracing equivalent of shadow acne).
- **@unchecked Sendable on AccelerationStructureManager** — the Metal objects it holds are thread-safe for read access during rendering, and mutation (rebuild/update) is expected to happen on one thread before rendering begins.
- **updateInstances()** — allows rebuilding just the instance acceleration structure when only transforms change (e.g., animated objects), without rebuilding the per-mesh primitive structures.

### Tradeoffs vs shadow maps

- **Quality**: Shadow maps have aliasing, acne, peter-panning. Ray traced shadows are pixel-perfect with no artifacts.
- **Performance**: Shadow maps are cheap (one extra depth pass). Ray tracing is more expensive (per-pixel ray cast).
- **Geometry**: Shadow maps work with any rasterizable geometry. Ray tracing needs acceleration structures built from triangle meshes.
- **Soft shadows**: Shadow maps use PCF approximation. Ray traced would need multiple rays (not implemented yet — single ray = hard shadows).
- **Dynamic geometry**: Shadow maps just re-render the depth pass. Ray tracing must rebuild/refit acceleration structures.

- `2026-04-13T23:03:52Z`: Implemented ray traced shadows using Metal ray tracing APIs
- `2026-04-13T23:11:15Z`: ## Design Overview

---

## 10: Shadow map: fix shadow acne / self-shadowing on teapot surfaces
status: closed
priority: high
kind: bug
created: 2026-04-13T18:47:31Z
updated: 2026-04-13T22:46:01Z
closed: 2026-04-13T22:46:01Z

With shadow debug enabled, teapot surfaces facing the light show as magenta (shadowed) due to self-shadowing artifacts. The bias direction in sample_compare needs to be corrected — subtracting bias makes it worse, adding bias breaks shadows entirely. Need to investigate proper bias strategy (e.g., slope-scale bias or receiver-plane bias).

- `2026-04-13T22:46:01Z`: Shadow acne resolved by hardware depth bias (setDepthBias + slopeScale) in the shadow map depth pass, with UI sliders for tuning. Shadows are now decoupled from Blinn-Phong into a screen-space shadow mask pass.

---

## 11: Shadow map: decouple shadow sampling from Blinn-Phong shader
status: closed
priority: medium
kind: feature
created: 2026-04-13T18:47:37Z
updated: 2026-04-13T22:03:02Z
closed: 2026-04-13T22:03:02Z

Decouple shadow mapping from Blinn-Phong into a screen-space shadow mask pass.

Pipeline:
1. Shadow map depth pass (from light's POV) — unchanged
2. Main color pass (Blinn-Phong or any shader — no shadow awareness)
3. Shadow mask pass (fullscreen quad, reads scene depth buffer + shadow map, outputs single-channel mask)
4. Composite pass (multiply color buffer by shadow mask)

Benefits:
- Lighting shaders stay clean — no shadow map parameters, textures, samplers, or function constants
- Shadow technique is swappable (PCF, VSM, PCSS, etc.) without touching lighting code
- Temporal accumulation or blur on the mask is easy to add
- Works with any lighting model (Blinn-Phong, flat, PBR, etc.)

Tradeoff: extra pass + bandwidth, but cheap on Apple Silicon tile-based architecture.

Requires: access to scene depth buffer as a texture in the shadow mask pass.

- `2026-04-13T22:03:02Z`: Implemented screen-space shadow mask pass. Shadow sampling is fully decoupled from Blinn-Phong: scene renders without shadow awareness, then a fullscreen ShadowMaskPass reads scene depth + shadow map and overlays shadows via alpha blending. Debug mode shows magenta overlay. All shadow code removed from BlinnPhongShaders.metal and BlinnPhongShader.swift.

---

## 12: Shadow map: sample_compare logic may be inverted
status: closed
priority: high
kind: bug
created: 2026-04-13T18:47:44Z
updated: 2026-04-13T20:02:39Z
closed: 2026-04-13T20:02:39Z

The comparison sampler uses .lessEqual and sample_compare returns 1.0 when storedDepth <= compareDepth. The current logic treats 1.0 as lit, but the teapots appear mostly magenta (shadowed) on light-facing surfaces. The comparison direction or the interpretation of the result may need to be inverted. Related to shadow acne issue #10.

- `2026-04-13T20:02:39Z`: Comparison logic is correct — the apparent issue was caused by the floor normal pointing down (#13), not inverted sample_compare.

---

## 13: Shadow map demo: floor is too dark
status: closed
priority: medium
kind: bug
created: 2026-04-13T18:47:51Z
updated: 2026-04-13T20:02:45Z
closed: 2026-04-13T20:02:45Z

Even with ambient light bumped to [0.3, 0.3, 0.35] and light intensity at 150, the ground plane appears too dark. The quadratic attenuation in the Blinn-Phong shader (1.0 / (1.0 + 0.09*d² + 0.032*d⁴)) heavily attenuates at the orbit distance (~7 units). Consider making attenuation configurable or using a less aggressive falloff.

- `2026-04-13T20:02:45Z`: Fixed: floor normal was [0,-1,0] (facing down) due to wrong rotation direction. Flipped to +π/2 so normal is [0,1,0]. Also switched to Unreal-style inverse-square attenuation and added editable ambient/intensity sliders.

---

## 14: Use inverse Z (reversed depth buffer) by default
status: closed
priority: medium
kind: enhancement
labels: rendering, depth-buffer, graphics, precision
created: 2026-04-13T19:58:58Z
updated: 2026-04-13T21:37:03Z
closed: 2026-04-13T21:37:03Z

Switch shadow map depth buffer to inverse Z (reversed depth). Changes needed:
- Shadow map orthographic projection: map near→1.0, far→0.0 instead of near→0.0, far→1.0
- Clear depth: 0.0 instead of 1.0
- Depth compare function: .greater instead of .less in the shadow depth pass
- Comparison sampler: .greaterEqual instead of .lessEqual
- sample_compare interpretation stays the same (1.0 = lit)
- Border color: .opaqueBlack instead of .opaqueWhite (fragments outside shadow map = depth 0.0 = far = lit)

Scope: shadow map only for now. Main scene depth pass is controlled by MetalSprockets/RenderView.

- `2026-04-13T21:37:03Z`: Inverse Z working: greaterEqual depth compare and sampler, negated depth bias for inverse Z, clear depth 0.0, border color opaqueBlack. Added DepthTextureView for live shadow map preview in inspector.

---

## 15: Support shadows with multiple lights and texture arrays
status: closed
priority: medium
kind: feature
labels: shadows, lighting, rendering, texture-array
created: 2026-04-13T20:03:45Z
updated: 2026-04-13T22:50:23Z
closed: 2026-04-13T22:50:23Z

Add support for shadow rendering when using multiple light sources. Investigate and implement texture arrays to efficiently manage shadow maps for multiple lights (e.g., shadow map atlases or array textures). This may include:
- Shadow casting/receiving for multiple simultaneous lights
- Texture array implementation for shadow maps
- Performance considerations for multi-light shadow rendering

- `2026-04-13T22:50:23Z`: Duplicate of #17 which has more detailed implementation plan.

---

## 16: ShadowMaskPass: use compute shader instead of fullscreen quad rasterization
status: new
priority: low
kind: enhancement
created: 2026-04-13T22:03:19Z

The shadow mask pass currently uses a fullscreen triangle with a raster pipeline and alpha blending. Replace with a compute shader that reads the scene depth texture and shadow map, computes the shadow factor, and writes directly to the color texture (read-modify-write). This avoids the overhead of a render pass and blending setup, and is more natural for a screen-space post-process on Apple Silicon.

---

## 17: Shadow map: support multiple lights using depth2d_array
status: closed
priority: medium
kind: feature
created: 2026-04-13T22:49:47Z
updated: 2026-04-13T23:04:03Z
closed: 2026-04-13T23:04:03Z

Support shadow maps for multiple lights. Use a depth2d_array texture to store all shadow maps, pass light view-projection matrices as an array, and loop over all lights in the ShadowMaskPass shader to combine shadow factors.

Changes needed:
- ShadowMap: allocate depth2d_array with one slice per light
- ShadowMapDepthPass: render each light's depth into its own array slice
- ShadowMaskPass shader: accept depth2d_array + array of light VP matrices, loop and multiply shadow factors
- ShadowMapParameters: extend to hold multiple light matrices and light count
- Demo: add a second light with its own shadow

- `2026-04-13T23:04:03Z`: Implemented: depth2d_array with one slice per light, separate depth passes per light, ShadowMapParameters extended with per-light matrices, sampleShadow loops over all lights and multiplies shadow factors. Demo has two orbiting lights with warm/cool colors and independent shadow maps visible in inspector.

---

## 18: Move demo code back into MetalSprocketsExamples
status: closed
priority: medium
kind: task
created: 2026-04-14T01:56:33Z
updated: 2026-04-14T02:52:39Z
closed: 2026-04-14T02:52:39Z

AddOns packages should NOT contain demo code. Move any demo code currently in MetalSprocketsAddOns back into MetalSprocketsExamples.

---

