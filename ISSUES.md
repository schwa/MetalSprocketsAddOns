# ISSUES.md

---

## 1: Replace histogram image comparison with GoldenImage package

+++
status: closed
priority: medium
kind: none
created: 2026-01-17T00:00:00Z
updated: 2026-04-19T20:33:41Z
closed: 2026-04-19T20:33:41Z
+++

The test Support.swift uses a homebrew histogram-based image comparison (vImage, CoreImage, Histogram struct). Replace this with the GoldenImage package which provides PSNR-based comparison. Requires publishing GoldenImage to GitHub first, then adding it as a dependency.

---

## 2: Remove local cross-environment macros and adopt them from MetalSprockets

+++
status: closed
priority: medium
kind: task
created: 2026-04-02T18:30:29Z
updated: 2026-04-02T18:43:48Z
closed: 2026-04-02T18:43:48Z
+++

Once MetalSprockets#305 is complete, remove the locally defined cross-environment macros from `Sources/MetalSprocketsAddOnsShaders/include/Support.h` (TEXTURE2D, DEPTH2D, TEXTURECUBE, SAMPLER, BUFFER, ATTRIBUTE, MS_ENUM) and import them from MetalSprockets instead.

Blocked on MetalSprockets#305.

---

## 3: Demo views render with wrong size/aspect ratio on initial load

+++
status: closed
priority: medium
kind: bug
created: 2026-04-13T05:04:24Z
updated: 2026-04-14T02:52:38Z
closed: 2026-04-14T02:52:38Z
+++

RenderView-based demos (Spinning Cube, GraphicsContext3D) render with incorrect aspect ratio or empty content on first load. Requires window resize or navigating away and back to fix. Likely caused by RenderView receiving a stale/zero drawable size before the NavigationSplitView detail column finishes layout. May be a DemoKit or MetalSprockets RenderView issue.

---

## 4: GraphicsContext3D fill renders as white instead of specified color

+++
status: new
priority: medium
kind: bug
created: 2026-04-13T05:07:02Z
updated: 2026-04-13T05:10:47Z
+++

Fill geometry in GraphicsContext3D renders as white when using fractional alpha (e.g. opacity 0.3). With full opacity the color is correct. The fill render pipeline has no blending enabled — alpha values are written to the framebuffer but don't affect compositing, resulting in near-white output for low-alpha fills. Need to enable alpha blending via renderPipelineDescriptorModifier on the fill pipeline.

---

## 5: GraphicsContext3D fill projection hardcoded to XY plane — fails for XZ/YZ geometry

+++
status: new
priority: medium
kind: bug
created: 2026-04-13T05:08:59Z
+++

generateFillGeometry() projects 3D points onto XY (drops Z) for earcut triangulation. This produces degenerate geometry for paths on the XZ or YZ planes (e.g. the star on the ground plane at y=0 — all points project to a line). Should detect the dominant plane or use the path's normal to choose the projection axis.

---

## 6: Integrate Slug text rendering into GraphicsContext3D

+++
status: new
priority: low
kind: feature
created: 2026-04-13T05:26:59Z
+++

Add a text drawing API to GraphicsContext3D (e.g. ctx.text("label", at: position, font:, color:)) that uses Slug for GPU-rendered text. Would allow placing text labels in 3D scenes without manually managing SlugScene/SlugTextMeshBuilder alongside the graphics context.

---

## 7: GraphicsContext3D does not render until window is resized

+++
status: closed
priority: high
kind: bug
created: 2026-04-13T17:21:37Z
updated: 2026-04-14T02:52:38Z
closed: 2026-04-14T02:52:38Z
+++

GraphicsContext3D content is completely invisible on initial load. Requires a window resize to trigger rendering. Affects both the standalone GraphicsContext3D demo and the BlinnPhong demo light marker. Possibly related to #3 (wrong size/aspect on initial load) but this is a complete rendering failure, not just wrong aspect.

---

## 8: Shadow map (rasterization-based) shadows

+++
status: closed
priority: medium
kind: feature
created: 2026-04-13T17:48:11Z
updated: 2026-04-13T19:44:23Z
closed: 2026-04-13T19:44:23Z
+++

Add shadow mapping support using a traditional rasterization approach. Render depth from the light's POV into a shadow map texture, then sample it in the fragment shader to determine shadow visibility. This avoids ray tracing entirely and can reuse existing pipeline patterns. Integrates with the existing Lighting and BlinnPhong infrastructure.

- `2026-04-13T19:44:23Z`: Basic shadow mapping working: depth pass renders from light POV, PCF sampling in Blinn-Phong shader, debug visualization toggle. Remaining issues tracked in #10, #11, #12, #13.

---

## 9: Ray traced shadows

+++
status: closed
priority: medium
kind: feature
created: 2026-04-13T17:48:18Z
updated: 2026-04-13T23:03:52Z
closed: 2026-04-13T23:03:52Z
+++

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

- `2026-04-13T17:48:18Z`: **Quality**: Shadow maps have aliasing, acne, peter-panning. Ray traced shadows are pixel-perfect with no artifacts.
- `2026-04-13T17:48:18Z`: **Performance**: Shadow maps are cheap (one extra depth pass). Ray tracing is more expensive (per-pixel ray cast).
- `2026-04-13T17:48:18Z`: **Geometry**: Shadow maps work with any rasterizable geometry. Ray tracing needs acceleration structures built from triangle meshes.
- `2026-04-13T17:48:18Z`: **Soft shadows**: Shadow maps use PCF approximation. Ray traced would need multiple rays (not implemented yet — single ray = hard shadows).
- `2026-04-13T17:48:18Z`: **Dynamic geometry**: Shadow maps just re-render the depth pass. Ray tracing must rebuild/refit acceleration structures.
- `2026-04-13T23:03:52Z`: Implemented ray traced shadows using Metal ray tracing APIs
- `2026-04-13T23:11:15Z`: ## Design Overview

---

## 10: Shadow map: fix shadow acne / self-shadowing on teapot surfaces

+++
status: closed
priority: high
kind: bug
created: 2026-04-13T18:47:31Z
updated: 2026-04-13T22:46:01Z
closed: 2026-04-13T22:46:01Z
+++

With shadow debug enabled, teapot surfaces facing the light show as magenta (shadowed) due to self-shadowing artifacts. The bias direction in sample_compare needs to be corrected — subtracting bias makes it worse, adding bias breaks shadows entirely. Need to investigate proper bias strategy (e.g., slope-scale bias or receiver-plane bias).

- `2026-04-13T22:46:01Z`: Shadow acne resolved by hardware depth bias (setDepthBias + slopeScale) in the shadow map depth pass, with UI sliders for tuning. Shadows are now decoupled from Blinn-Phong into a screen-space shadow mask pass.

---

## 11: Shadow map: decouple shadow sampling from Blinn-Phong shader

+++
status: closed
priority: medium
kind: feature
created: 2026-04-13T18:47:37Z
updated: 2026-04-13T22:03:02Z
closed: 2026-04-13T22:03:02Z
+++

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

+++
status: closed
priority: high
kind: bug
created: 2026-04-13T18:47:44Z
updated: 2026-04-13T20:02:39Z
closed: 2026-04-13T20:02:39Z
+++

The comparison sampler uses .lessEqual and sample_compare returns 1.0 when storedDepth <= compareDepth. The current logic treats 1.0 as lit, but the teapots appear mostly magenta (shadowed) on light-facing surfaces. The comparison direction or the interpretation of the result may need to be inverted. Related to shadow acne issue #10.

- `2026-04-13T20:02:39Z`: Comparison logic is correct — the apparent issue was caused by the floor normal pointing down (#13), not inverted sample_compare.

---

## 13: Shadow map demo: floor is too dark

+++
status: closed
priority: medium
kind: bug
created: 2026-04-13T18:47:51Z
updated: 2026-04-13T20:02:45Z
closed: 2026-04-13T20:02:45Z
+++

Even with ambient light bumped to [0.3, 0.3, 0.35] and light intensity at 150, the ground plane appears too dark. The quadratic attenuation in the Blinn-Phong shader (1.0 / (1.0 + 0.09*d² + 0.032*d⁴)) heavily attenuates at the orbit distance (~7 units). Consider making attenuation configurable or using a less aggressive falloff.

- `2026-04-13T20:02:45Z`: Fixed: floor normal was [0,-1,0] (facing down) due to wrong rotation direction. Flipped to +π/2 so normal is [0,1,0]. Also switched to Unreal-style inverse-square attenuation and added editable ambient/intensity sliders.

---

## 14: Use inverse Z (reversed depth buffer) by default

+++
status: closed
priority: medium
kind: enhancement
labels: rendering, depth-buffer, graphics, precision
created: 2026-04-13T19:58:58Z
updated: 2026-04-13T21:37:03Z
closed: 2026-04-13T21:37:03Z
+++

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

+++
status: closed
priority: medium
kind: feature
labels: shadows, lighting, rendering, texture-array
created: 2026-04-13T20:03:45Z
updated: 2026-04-13T22:50:23Z
closed: 2026-04-13T22:50:23Z
+++

Add support for shadow rendering when using multiple light sources. Investigate and implement texture arrays to efficiently manage shadow maps for multiple lights (e.g., shadow map atlases or array textures). This may include:

- `2026-04-13T20:03:45Z`: Shadow casting/receiving for multiple simultaneous lights
- `2026-04-13T20:03:45Z`: Texture array implementation for shadow maps
- `2026-04-13T20:03:45Z`: Performance considerations for multi-light shadow rendering
- `2026-04-13T22:50:23Z`: Duplicate of #17 which has more detailed implementation plan.

---

## 16: ShadowMaskPass: use compute shader instead of fullscreen quad rasterization

+++
status: new
priority: low
kind: enhancement
created: 2026-04-13T22:03:19Z
+++

The shadow mask pass currently uses a fullscreen triangle with a raster pipeline and alpha blending. Replace with a compute shader that reads the scene depth texture and shadow map, computes the shadow factor, and writes directly to the color texture (read-modify-write). This avoids the overhead of a render pass and blending setup, and is more natural for a screen-space post-process on Apple Silicon.

---

## 17: Shadow map: support multiple lights using depth2d_array

+++
status: closed
priority: medium
kind: feature
created: 2026-04-13T22:49:47Z
updated: 2026-04-13T23:04:03Z
closed: 2026-04-13T23:04:03Z
+++

Support shadow maps for multiple lights. Use a depth2d_array texture to store all shadow maps, pass light view-projection matrices as an array, and loop over all lights in the ShadowMaskPass shader to combine shadow factors.

Changes needed:

- `2026-04-13T22:49:47Z`: ShadowMap: allocate depth2d_array with one slice per light
- `2026-04-13T22:49:47Z`: ShadowMapDepthPass: render each light's depth into its own array slice
- `2026-04-13T22:49:47Z`: ShadowMaskPass shader: accept depth2d_array + array of light VP matrices, loop and multiply shadow factors
- `2026-04-13T22:49:47Z`: ShadowMapParameters: extend to hold multiple light matrices and light count
- `2026-04-13T22:49:47Z`: Demo: add a second light with its own shadow
- `2026-04-13T23:04:03Z`: Implemented: depth2d_array with one slice per light, separate depth passes per light, ShadowMapParameters extended with per-light matrices, sampleShadow loops over all lights and multiplies shadow factors. Demo has two orbiting lights with warm/cool colors and independent shadow maps visible in inspector.

---

## 18: Move demo code back into MetalSprocketsExamples

+++
status: closed
priority: medium
kind: task
created: 2026-04-14T01:56:33Z
updated: 2026-04-14T02:52:39Z
closed: 2026-04-14T02:52:39Z
+++

AddOns packages should NOT contain demo code. Move any demo code currently in MetalSprocketsAddOns back into MetalSprocketsExamples.

---

## 19: AccelerationStructureManager should accept Mesh (not just MTKMesh) and expose enough API for external extension

+++
status: new
priority: high
kind: enhancement
created: 2026-04-14T23:50:30Z
+++

AccelerationStructureManager.build() only accepts [MTKMesh], but projects using the custom Mesh type (e.g. MetalSprocketsSceneGraph) cannot build acceleration structures without converting to MTKMesh.\n\nAdditionally, the struct's internals (device, commandQueue, primitiveAccelerationStructures setter, instanceAccelerationStructure setter, buildAccelerationStructure(descriptor:), buildInstanceAccelerationStructure(...)) are all private, making it impossible to add a Mesh overload via extension from another module.\n\nEither:\n1. Add a build(meshes: [Mesh], instances:) overload, or\n2. Make enough internals internal/public to allow external extensions.

---

## 20: MeshWithEdges edge extraction produces wrong indices with MetalMesh

+++
status: closed
priority: medium
kind: bug
created: 2026-04-15T01:36:37Z
updated: 2026-04-15T01:37:23Z
closed: 2026-04-15T01:37:23Z
+++

MetalMesh splits vertices per-corner (each half-edge corner becomes a unique vertex in the output buffer). MeshWithEdges.init(metalMesh:) reads the raw index buffer, so the extracted edges reference these per-corner indices instead of the original shared vertex indices. This means shared edges between triangles are never deduplicated — e.g. a cube produces 50 edges instead of 18. Either MeshWithEdges needs to work in terms of per-corner indices (and tests updated), or it needs a way to map back to original vertex positions to identify shared edges.

- `2026-04-15T01:37:23Z`: Filed against SwiftMesh instead (#SwiftMesh#22)

---

## 21: BlinnPhongShader and DebugRenderPipeline tests render black (likely vertex-buffer index collision)

+++
status: new
priority: medium
kind: bug
labels: testing, shader
created: 2026-04-19T19:53:17Z
+++

Five golden-image tests are currently disabled with `.disabled(\"Renders black — see FIXME above\")` because the resulting render is entirely (or near-entirely) black even though the pipeline runs end-to-end without errors:

- `testBlinnPhongShader_litBox` (Tests/MetalSprocketsAddOnsTests/BlinnPhongShaderTests.swift)
- `testBlinnPhongShader_litSphereTwoLights` (Tests/MetalSprocketsAddOnsTests/BlinnPhongShaderTests.swift)
- `testDebugRenderPipeline_normalMode` (Tests/MetalSprocketsAddOnsTests/DebugRenderPipelineTests.swift)
- `testDebugRenderPipeline_localPositionMode` (Tests/MetalSprocketsAddOnsTests/DebugRenderPipelineTests.swift)
- `testDebugRenderPipeline_faceNormalMode` (Tests/MetalSprocketsAddOnsTests/DebugRenderPipelineTests.swift)

## Root cause hypothesis

`BlinnPhongShaders.metal` and `DebugShaders.metal` bind uniforms at vertex/fragment buffer indices 1, 2, 3. The test meshes are built via `MDLMesh.addNormals` + `addTangentBasis`, which produces a vertex layout that uses **multiple vertex buffer indices** (buffer 0 for position+normal+texCoord, buffer 1+ for tangent/bitangent). The mesh's `setVertexBuffers(of:)` then binds the tangent buffer at index 1, **clobbering the shader's `modelViewMatrix [[buffer(1)]]` uniform**. Net result: matrices are effectively zero, fragments shade against an all-zero MVP, output is black.

The Lambertian, Wireframe, and FlatShader tests use the same mesh helpers but those shaders consume their uniforms at higher buffer indices (or accept inferred descriptors), so they render correctly.

## Coverage impact

Disabling these tests dropped coverage on the affected files back to 0%:
- `BlinnPhongShader.swift` (18 lines)
- `BlinnPhongShader+Support.swift` (32 lines)
- `Lighting.swift` (42 lines)
- `DebugRenderPipeline.swift` (36 lines)

Re-enabling will recover ~3% of total line coverage.

## Suggested fix paths

1. Build the test mesh into a single interleaved vertex buffer (manually constructed `MDLVertexBufferLayout` with `stride` and `bufferIndex: 0` for all attributes), so no mesh-side buffer binds collide with shader uniform indices.
2. Or rebind shader uniforms to higher buffer indices (e.g. 16+) in the relevant Metal shaders.
3. Or add a test fixture that vendors a small teapot (`MTKMesh.teapot()` from MetalSprocketsExamples support) so we render against a known-good mesh layout.

Once fixed, remove the `.disabled(...)` arguments from the five tests, refresh their golden PNGs, and verify the rendered output is non-black.

---

## 22: ShadowMapDepthPass renders fail under OffscreenRenderer (nested RenderPass + command encoder collision)

+++
status: new
priority: low
kind: bug
labels: testing, shader
created: 2026-04-19T20:04:33Z
+++

An end-to-end test for `ShadowMapDepthPass` + `ShadowMaskPass` triggers a Metal
assertion when run via `OffscreenRenderer`:

```
-[AGXG17XFamilyCommandBuffer renderCommandEncoderWithDescriptor:]:967:
  failed assertion 'A command encoder is already encoding to this command buffer'
```

`ShadowMapDepthPass` internally nests `try RenderPass { ... }` per shadow-casting
light (one render pass per array slice of the depth texture). When this is run
through `OffscreenRenderer`, the outer renderer has already created a command
buffer + open render command encoder, and the nested per-light render passes try
to open a second encoder on the same command buffer.

## Coverage impact

`ShadowMapRenderPipeline.swift` has its `ShadowMap` struct + matrix helpers covered
(44.7%) by direct unit tests, but the `ShadowMapDepthPass` `body` implementation
and the entire `ShadowMaskPass` (78 lines) are uncovered until this is resolved.

## Likely fixes

1. `OffscreenRenderer` should support hosting elements that emit their own render
   passes (commit/end the outer encoder when entering a child pass).
2. Or expose a lower-level `OffscreenContext` that a test can use to drive nested
   render passes manually.
3. Or refactor `ShadowMapDepthPass` to render all light slices via a single
   render-target-array render pass rather than N nested passes.

When fixed, restore the `testShadowPipelines_depthPassThenMaskPass_renders` test
(see git history of `Tests/MetalSprocketsAddOnsTests/ShadowMapTests.swift`).

---

## 23: Remove dead code in ColorSource (private color accessor + unused Element.useResource modifier)

+++
status: new
priority: low
kind: enhancement
labels: cleanup
created: 2026-04-19T20:18:18Z
+++

Two methods in `Sources/MetalSprocketsAddOns/Support/ColorSource.swift` are never
called anywhere in the codebase and remain at 0% coverage despite a comprehensive
unit-test suite for `ColorSource`:

1. `private var color: SIMD3<Float>?` (lines 48-53) — a private case-extracting
   accessor that is never read (the `.color` case is destructured in `toArgumentBuffer`
   directly).

2. `public extension Element { func useResource(_ color: ColorSource, ...) }`
   (lines 82-91) — a public modifier helper that no caller uses. The implementation
   only forwards `texture2D`; the `textureCube` and `depth2D` calls are commented
   out (see TODO `uv-eg-3` referencing iOS/macOS hangs with argument buffers).

## Suggested action

- Delete the private `color` accessor outright (no behavior change).
- For the `Element.useResource(_ color:)` extension: either remove it (since no one
  uses it) or wire it into the pipelines that bind `ColorSource` argument buffers
  (`FlatShader`, `TextureBillboardPipeline`, `TexturedQuad3D`) which currently
  call `useResource` on the underlying `MTLTexture` directly.

Once removed/wired, `ColorSource.swift` should reach ~100% coverage from the
existing tests in `Tests/MetalSprocketsAddOnsTests/ColorSourceTests.swift`.

---

## 24: Element.lighting(_:) modifier has no coverage outside disabled BlinnPhong tests

+++
status: new
priority: low
kind: enhancement
labels: cleanup
depends: MetalSprocketsAddOns#21
created: 2026-04-19T20:18:23Z
+++

The `Element.lighting(_:)` modifier in
`Sources/MetalSprocketsAddOns/Pipelines/Lighting.swift` (lines 60-66) is only
called by `BlinnPhongShader` test paths and the disabled BlinnPhong tests
(see issue #21). It currently sits at 0% coverage.

```swift
public extension Element {
    func lighting(_ lighting: Lighting) throws -> some Element {
        self
            .parameter("lighting", value: try lighting.toArgumentBuffer())
            .useResource(lighting.lights, usage: .read, stages: .fragment)
            .useResource(lighting.lightPositions, usage: .read, stages: .fragment)
    }
}
```

The other Lighting consumer in the addon — `RayTracedShadowComputePass` — does
not use this modifier; it calls `lighting.toArgumentBuffer()` directly and
binds the buffers via `setBytes` / `useResource` on the compute encoder.

## Suggested action

When BlinnPhong tests are re-enabled (issue #21), this modifier will get
coverage. Until then, consider:

- Leave as-is (it's a public API consumers might use).
- Or move into `BlinnPhongShader+Support.swift` since BlinnPhong is the only
  caller.
- Or remove if BlinnPhong is refactored to call `toArgumentBuffer()` /
  `useResource` directly like the RT path does.

---

## 25: GraphicsContext3D fill of curved paths renders angular shapes (low-resolution subdivision)

+++
status: new
priority: low
kind: bug
created: 2026-04-19T20:42:15Z
+++

When `GraphicsContext3D.fill(_:with:)` is given a path containing
`addQuadCurve` / `addCurve` segments, the rendered fill looks angular even
though `GeometryGenerator.extractPoints(from:)` calls `subdivideQuadCurve`
(adaptive, up to 40 segments) and `subdivideCubicCurve`.

Reproduce with the test `testGraphicsContext3D_strokedEllipse` /
the (now-removed) `testGraphicsContext3D_filledShapeWithCurves`: a
4-quad-curve ellipse approximation renders as a "lemon" shape with sharp
left/right corners rather than smooth arcs.

Hypothesis: the adaptive subdivision uses `estimateQuadCurveScreenLength`
which projects the curve through `viewProjection` to estimate pixel length.
For a small render target (256×256 in tests) this yields very few segments
(maybe 3-4 per quarter arc), producing the visible polygonal silhouette.

## Suggested investigation

- Print the segment count for the four ellipse quarter-arcs at 256×256 vs.
  1024×1024 to confirm.
- Consider raising the floor (currently `max(3, ...)`).
- Or expose the segment count / `pixelsPerSegment` as a tunable on
  `GraphicsContext3DRenderPipeline`.

---

## 26: GraphicsContext3D stroke line width varies along curved paths

+++
status: new
priority: low
kind: bug
created: 2026-04-19T20:42:23Z
+++

When `GraphicsContext3D.stroke(_:with:style:)` strokes a curved path with
a constant `lineWidth`, the rendered line width visibly varies along the path.

Reproduce with `testGraphicsContext3D_strokedEllipse`: a 6pt round-cap stroke
of a 4-quad-curve ellipse (rx=0.55, ry=0.4) renders chunky on the top/bottom
arcs and noticeably thinner on the left/right arcs.

Hypothesis: line width is applied per-segment in screen space, but the
per-vertex extrusion direction may not be normalized correctly when the
underlying segment is short (subdivided curves produce tiny segments at low
resolutions, see related issue about fill curves looking angular). Cap/join
overlap may also contribute.

## Suggested investigation

- Log the per-segment screen lengths for the ellipse arcs.
- Inspect `LineJoinGPUData.normal` computation around the curve endpoints.
- Check whether the `.round` join interpolation is using arc length or
  segment count.

---

## 27: Element.useResource(_ color:) skips textureCube and depth2D (uv-eg-3 workaround)

+++
status: new
priority: low
kind: bug
created: 2026-04-19T20:42:31Z
+++

In `Sources/MetalSprocketsAddOns/Support/ColorSource.swift`, the
`Element.useResource(_ color:usage:stages:)` modifier deliberately omits
`useResource` calls for the `textureCube` and `depth2D` cases:

```swift
public extension Element {
    func useResource(_ color: ColorSource, usage: MTLResourceUsage, stages: MTLRenderStages) -> some Element {
        self
            .useResource(color.texture2D, usage: usage, stages: stages)
        // uv-eg-3: textureCube and depth2D useResource calls cause hangs on iOS/macOS
        // Only texture2D works reliably when used with argument buffers
        //            .useResource(color.textureCube, usage: usage, stages: stages)
        //            .useResource(color.depth2D, usage: usage, stages: stages)
    }
}
```

The "uv-eg-3" reference suggests this was a workaround for a specific bug.
Effects:

1. Anyone consuming a `ColorSource.textureCube(...)` or `.depth2D(...)`
   through this modifier silently gets no useResource declaration for
   that texture, which can lead to GPU hangs / validation errors when
   the argument buffer is later sampled.
2. The modifier is currently called by no addon code (see issue #23),
   so the missing branches don't bite us in practice — but anyone who
   adopts it externally for cube/depth ColorSources will hit issues.

## Suggested action

Investigate whether the `uv-eg-3` workaround still applies on current
macOS / iOS, and either:

- Re-enable the cube/depth `useResource` calls if the hang is fixed; or
- Remove this modifier entirely (per #23, no caller currently uses it); or
- Document the limitation in the public API docstring so consumers know
  to call `useResource` manually for cube/depth ColorSources.

Cross-references: #23 (dead code in ColorSource).

---

## 28: Bump golden-image render size from 256x256 to 512x512

+++
status: new
priority: low
kind: enhancement
labels: testing
created: 2026-04-19T20:42:56Z
+++

All golden-image tests currently render at 256×256 (set by
`defaultRenderSize` in `Tests/MetalSprocketsAddOnsTests/Support/RenderTestSupport.swift`).
At this resolution several pipelines produce visibly degraded output that
makes the goldens hard to inspect:

- `GraphicsContext3D` curve subdivision is too coarse (see #25, #26): the
  4-quad-curve ellipse renders as a "lemon" / blobby diamond.
- `RayTracedShadowSphere` shadow edge is heavily aliased.
- Some Slug text glyphs render at sub-pixel sizes.

Bump `defaultRenderSize` to **512×512** for all golden-image tests, then
regenerate every golden PNG once and commit the updated set.

## Suggested action

1. Change `defaultRenderSize` from 256×256 to 512×512 in `RenderTestSupport.swift`.
2. Delete every golden PNG that uses `defaultRenderSize` (most of them).
3. Run the test suite once; the GoldenImage library writes the new PNGs to
   `/tmp/<name>.png` on the first miss.
4. Inspect each new render visually, then promote them into
   `Tests/MetalSprocketsAddOnsTests/Golden Images/`.
5. Tests outside the default size (e.g. `GaussianBlurSquare` at 128×128) can
   stay at their explicit sizes if there's a reason.

## Cost

- Larger goldens → bigger repo. Most current PNGs are 1.7-15 KB; at 512×512
  they'll be ~4-50 KB each. With ~30 goldens this adds maybe 1 MB total.
- One-time regeneration effort.

---

## 29: testGraphicsContext3D_filledQuad crashes on CI (Apple paravirt GPU)

+++
status: new
priority: medium
kind: bug
labels: testing, ci
created: 2026-04-19T20:49:27Z
+++

`testGraphicsContext3D_filledQuad` (in
`Tests/MetalSprocketsAddOnsTests/GraphicsContext3DTests.swift`) crashes the test
process when run on GitHub Actions `macos-26` runners (Apple paravirtualized
GPU).

## Symptom

```
*** Terminating app due to uncaught exception 'NSInvalidArgumentException',
    reason: '-[AppleParavirtRenderCommandEncoder setMeshBuffer:offset:atIndex:]:
    unrecognized selector sent to instance 0xad2474000'
libc++abi: terminating due to uncaught exception of type NSException
error: Exited with unexpected signal code 6
```

The crash aborts the entire `MetalSprocketsAddOnsPackageTests` process so no
subsequent tests run.

## Reproduction

- GitHub Actions run: <https://github.com/schwa/MetalSprocketsAddOns/actions/runs/24638506941>
- Workflow: `.github/workflows/swift.yml` (`swift-build-26` job)
- Local runs (Apple silicon, real GPU) pass cleanly.

## Workaround

Test is currently disabled on CI via:

```swift
@Test(.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil,
                "Crashes on CI paravirt GPU — see issue #29"))
```

## What we know

- The CI host uses an `AppleParavirtRenderCommandEncoder` (paravirtualized GPU
  exposed inside the GitHub Actions VM).
- The selector `setMeshBuffer:offset:atIndex:` is part of the mesh-shader API.
  `GraphicsContext3D` does **not** use mesh shaders — only plain vertex/fragment
  shaders — so it is unclear why this selector is being dispatched against the
  fill render encoder.
- Other tests in the same suite that DO use mesh shaders (e.g.
  `EdgeLinesRenderPipeline*`) and ray tracing
  (`AccelerationStructureManager*`, `RayTracedShadowComputePass*`) almost
  certainly fail on this hardware too, but we have no direct evidence yet
  because the suite aborts before reaching them.

## Next steps

1. Re-enable the test on CI once we either:
   - Confirm the underlying issue is in MetalSprockets / GraphicsContext3D's
     parameter-binding code path and fix it; or
   - Determine the paravirt GPU genuinely cannot run this pipeline and gate it
     properly (e.g. via a runtime feature check rather than `CI` env var).
2. Verify whether the mesh-shader and RT tests also fail on CI (run them
   individually now that the suite can complete).

- `2026-04-19T21:55:57Z`: More CI paravirt GPU breakage observed (after disabling the originally
crashing tests):

## Texture sampling returns broken values on CI

Five additional tests fail on GitHub Actions `macos-26` runners — but pass
on a local VirtualBuddy paravirt VM. Pulled from CI artifact
`golden-image-mismatches`:

| Test | Local VM render | CI render |
|---|---|---|
| `testFlatShaderWithTexture` | blue/green checkerboard | solid white quad |
| `testTextureBillboardPipeline_checkerboard` | dark/light checkerboard | solid white |
| `testTextureBillboardPipeline_upperRightQuadrant` | checkerboard in UR quadrant | solid white in UR quadrant |
| `testTexturedQuad3DPipeline_mandrillFlat` (YCbCr) | mandrill | solid green |
| `testTexturedQuad3DPipeline_mandrillRotatedInPerspective` (YCbCr) | mandrill | solid green |

Geometry renders correctly in every case — only the texture sample
returns a constant value:
- Plain `.rgba8Unorm` sampling → returns `(1, 1, 1, 1)` (white)
- YCbCr two-plane sampling (`r8Unorm` + `rg8Unorm`) → returns `(0, 1, 0, 1)`
  (green; consistent with Y=0, Cb=0, Cr=0 going through the YCbCr→RGB
  matrix)

So the GitHub Actions paravirt driver returns zeros (or default border
color) for `texture.sample(...)` instead of the actual texel data. Local
paravirt (Tahoe-based VirtualBuddy VM) samples textures correctly.

## Mitigation

All 5 tests now have:
```swift
@Test(.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil,
                "Texture sampling broken on CI paravirt GPU — see issue #29"))
```

## Total tests now disabled on CI

| File | Count | Reason |
|---|---|---|
| GraphicsContext3DTests | 6 | `setMeshBuffer:` selector crash |
| EdgeLinesRenderPipelineTests | 3 | mesh shaders unsupported |
| AccelerationStructureManagerTests | 5 | `device.supportsRaytracing == false` |
| RayTracedShadowComputePassTests | 1 | same |
| FlatShaderTests | 1 | texture sampling broken |
| TextureBillboardPipelineTests | 2 | texture sampling broken |
| TexturedQuad3DPipelineTests | 2 | YCbCr texture sampling broken |
| **Total** | **20** | of 129 |

So CI now exercises 109 of the 129 tests. All the disabled tests still
run locally (and on a VirtualBuddy paravirt VM).

## Related to original report

The `setMeshBuffer:` crash was the surface symptom; texture-sampling
failure is a separate but related GPU driver gap on the GitHub Actions
runner image. Worth keeping eye on whether GitHub upgrades the runner
host's macOS / paravirt driver in future image rolls — these tests can be
re-enabled if/when that happens.

---

## 30: Support equirectangular and other sky map modes in SkyboxRenderPipeline

+++
status: new
priority: medium
kind: feature
created: 2026-05-21T03:32:30Z
+++

Today `SkyboxRenderPipeline` only supports cubemap textures. Real-world sky/star maps (e.g. Tycho skymap, HDRI environments from Poly Haven) are usually distributed as **equirectangular** (lat-long) panoramas, and occasionally as horizontal/vertical cross layouts.

Currently users have to either:
- Pre-convert their equirectangular textures to cubemaps offline, or
- Reimplement the panorama shader themselves (as the `PanoramaDemo` in MetalSprocketsExamples does).

### Proposal

Extend the skybox support to handle multiple input formats. Options:

1. Add a new `PanoramaSkyboxRenderPipeline` that takes a 2D equirectangular texture and renders it via an inward-facing sphere or a fullscreen-pass + direction-to-UV conversion (see `MetalSprocketsExamples/.../PanoramaDemo/PanoramaShaders.metal`).
2. Or: make `SkyboxRenderPipeline` polymorphic over a `SkyMapMode` enum (`.cube`, `.equirectangular`, `.horizontalCross`, `.verticalCross`) and pick the right shader internally.
3. Provide a helper that converts an equirectangular texture to a cubemap at load time (one-shot compute pass), so the existing pipeline keeps working unchanged.

Option 1 or 2 is preferred — option 3 wastes memory for what is essentially a UV transform.

### Use case

Planet/space scenes commonly want a starfield from sources like the Tycho skymap, which ships as a 16384x8192 equirectangular JPEG. The fullscreen technique already used in the existing `SkyboxRenderPipeline` (inverse view-projection per pixel) maps cleanly to equirectangular sampling — just replace the cubemap sample with a direction-to-(u,v) conversion.

---
