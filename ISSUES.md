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
status: closed
priority: medium
kind: bug
labels: effort:s
created: 2026-04-13T05:07:02Z
updated: 2026-08-09T00:20:42Z
closed: 2026-08-09T00:20:42Z
+++

Fill geometry in GraphicsContext3D renders as white when using fractional alpha (e.g. opacity 0.3). With full opacity the color is correct. The fill render pipeline has no blending enabled — alpha values are written to the framebuffer but don't affect compositing, resulting in near-white output for low-alpha fills. Need to enable alpha blending via renderPipelineDescriptorModifier on the fill pipeline.

---

## 5: GraphicsContext3D fill projection hardcoded to XY plane — fails for XZ/YZ geometry

+++
status: closed
priority: medium
kind: bug
labels: effort:m
created: 2026-04-13T05:08:59Z
updated: 2026-08-09T00:22:08Z
closed: 2026-08-09T00:22:08Z
+++

generateFillGeometry() projects 3D points onto XY (drops Z) for earcut triangulation. This produces degenerate geometry for paths on the XZ or YZ planes (e.g. the star on the ground plane at y=0 — all points project to a line). Should detect the dominant plane or use the path's normal to choose the projection axis.

---

## 6: Integrate Slug text rendering into GraphicsContext3D

+++
status: closed
priority: low
kind: feature
labels: effort:l
created: 2026-04-13T05:26:59Z
updated: 2026-08-09T01:27:30Z
closed: 2026-08-09T01:27:30Z
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
status: closed
priority: low
kind: enhancement
labels: effort:m
created: 2026-04-13T22:03:19Z
updated: 2026-08-09T00:42:40Z
closed: 2026-08-09T00:42:40Z
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
status: closed
priority: high
kind: enhancement
labels: effort:m
created: 2026-04-14T23:50:30Z
updated: 2026-08-09T00:37:29Z
closed: 2026-08-09T00:37:29Z
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
status: closed
priority: medium
kind: bug
labels: testing, shader, effort:m
created: 2026-04-19T19:53:17Z
updated: 2026-08-09T00:38:18Z
closed: 2026-08-09T00:38:18Z
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
status: closed
priority: low
kind: bug
labels: testing, shader, effort:l
created: 2026-04-19T20:04:33Z
updated: 2026-08-09T00:40:13Z
closed: 2026-08-09T00:40:13Z
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

- `2026-08-09T00:13:48Z`: Related: #40 — the same nested-RenderPass-in-OffscreenRenderer limitation is what leaves the shadow chain untested there.

---

## 23: Remove dead code in ColorSource (private color accessor + unused Element.useResource modifier)

+++
status: closed
priority: low
kind: enhancement
labels: cleanup, effort:xs
created: 2026-04-19T20:18:18Z
updated: 2026-08-09T00:18:40Z
closed: 2026-08-09T00:18:40Z
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
status: closed
priority: low
kind: enhancement
labels: cleanup, effort:xs
depends: MetalSprocketsAddOns#21
created: 2026-04-19T20:18:23Z
updated: 2026-08-09T00:40:02Z
closed: 2026-08-09T00:40:02Z
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
status: closed
priority: low
kind: bug
labels: effort:s
created: 2026-04-19T20:42:15Z
updated: 2026-08-09T00:25:59Z
closed: 2026-08-09T00:25:59Z
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

- `2026-08-09T00:13:48Z`: Related: #28 — raising the golden render size to 512x512 may change the observed subdivision quality; investigate together.

---

## 26: GraphicsContext3D stroke line width varies along curved paths

+++
status: closed
priority: low
kind: bug
labels: effort:m
created: 2026-04-19T20:42:23Z
updated: 2026-08-09T00:30:45Z
closed: 2026-08-09T00:30:45Z
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

\- `2026-08-09T00:13:48Z`: Related: #25 and #28 — same curve-subdivision/render-size area.
\- `2026-08-09T00:30:45Z`: Investigated with a pixel-level measurement harness: rendered a stroked circle (lineWidth 6, round cap/join) offscreen at 512x512 and 1024x1024, bucketed every lit pixel by angle, and measured the ring's radial thickness per 10-degree wedge.

- Original tree: thickness ranged 5.86px to 8.44px (44% variation) — reproduces the report.
- After the #25 fix: 5.75px to 5.99px, i.e. uniform to within pixel quantization.

Root cause was the same as #25: the four-arc ellipse test fixture used the cubic control constant in addQuadCurve, leaving an ~18 degree tangent discontinuity at each quadrant. The round joins piled up at those kinks (chunky) while the over-flat arcs between them read as thin. The screen-space extrusion in the mesh shader was measured correct throughout.

Closing with a new regression test, testGraphicsContext3D_strokeWidthIsUniformAlongCurves, which pins the ring thickness to lineWidth +/- 0.75px in every wedge; it fails on the pre-#25 tree and passes now.

---

## 27: Element.useResource(_ color:) skips textureCube and depth2D (uv-eg-3 workaround)

+++
status: closed
priority: low
kind: bug
labels: effort:s
created: 2026-04-19T20:42:31Z
updated: 2026-08-09T00:19:06Z
closed: 2026-08-09T00:19:06Z
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

- `2026-08-09T00:13:48Z`: Related: #23 — if the Element.useResource(_ color:) modifier is deleted per #23, this issue becomes moot.

---

## 28: Bump golden-image render size from 256x256 to 512x512

+++
status: closed
priority: low
kind: enhancement
labels: testing, effort:m
created: 2026-04-19T20:42:56Z
updated: 2026-08-09T01:23:19Z
closed: 2026-08-09T01:23:19Z
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
status: closed
priority: medium
kind: bug
labels: testing, ci, effort:l
created: 2026-04-19T20:49:27Z
updated: 2026-08-09T00:39:59Z
closed: 2026-08-09T00:39:59Z
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

\- `2026-04-19T21:55:57Z`: More CI paravirt GPU breakage observed (after disabling the originally
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

\- `2026-08-09T00:39:59Z`: Fixed. Root cause: GraphicsContext3DRenderPipeline always emitted its stroke MeshRenderPipeline, even for fill-only contexts. The Draw closure guarded on joinCount, but the .parameter(..., functionType: .mesh, ...) bindings were applied unconditionally, so setMeshBuffer:offset:atIndex: was still sent to the encoder — fatal on a paravirt GPU with no mesh-stage selectors.

Both pipelines are now only built when they have geometry (joinCount > 0 / fillVertexCount > 0), so fill-only contexts never touch the mesh path. testGraphicsContext3D_filledQuad and testGraphicsContext3D_fillRespectsAlpha are re-enabled everywhere.

The remaining GPU-feature gates now use runtime probes instead of the CI env var (Tests/MetalSprocketsAddOnsTests/Support/GPUCapabilities.swift):
- supportsMeshShaders: probes whether a real MTLRenderCommandEncoder responds to setMeshBuffer:offset:atIndex: — used by the 6 GraphicsContext3D stroke tests and the 3 EdgeLines tests.
- supportsRaytracing: device.supportsRaytracing — used by the 5 AccelerationStructureManager tests and the 1 RayTracedShadowComputePass test.

CI-env gating for the 5 texture-sampling tests remains and is split out to #44.

Local: 150 tests pass, none skipped.

---

## 30: Support equirectangular and other sky map modes in SkyboxRenderPipeline

+++
status: closed
priority: medium
kind: feature
created: 2026-05-21T03:32:30Z
updated: 2026-05-21T03:40:32Z
closed: 2026-05-21T03:40:32Z
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

## 31: VideoTexturePipeline has unsynchronized mutable state across isolation boundaries

+++
status: closed
priority: high
kind: bug
labels: concurrency, effort:m
created: 2026-08-09T00:09:03Z
updated: 2026-08-09T00:19:56Z
closed: 2026-08-09T00:19:56Z
+++

VideoTexturePipeline is declared @unchecked Sendable but provides no synchronization for any of its stored properties.

All stored properties are mutable with no lock and no actor isolation: player, playerItem, videoOutput, updateTask, currentTexture, textureCache, loopStart, loopEnd.

They are accessed from mixed isolation domains:
- loadVideo(url:loopStart:loopEnd:) and updateFrame() are @MainActor.
- init(device:), play(), pause(), and deinit are nonisolated and touch the same storage.
- @Observable additionally exposes currentTexture for reads from any thread.

The @unchecked Sendable conformance suppresses the compiler diagnostics that would otherwise flag this; it does not make the type thread-safe.

Concrete races:
- play() and pause() called from different threads both write updateTask.
- updateFrame() writes currentTexture on the main actor while a renderer reads it from a render thread.
- deinit calls player?.pause() from whatever thread releases the last reference.

Env: Swift 6.2, strict concurrency. Package currently builds without warnings because of the @unchecked escape hatch.

---

## 32: VideoTexturePipeline.play() leaks its update task and never deallocates during playback

+++
status: closed
priority: high
kind: bug
labels: concurrency, effort:s
created: 2026-08-09T00:09:12Z
updated: 2026-08-09T00:21:11Z
closed: 2026-08-09T00:21:11Z
+++

Two related lifecycle defects in VideoTexturePipeline.play().

1. The update task strongly captures self.

play() assigns updateTask = Task { ... } and the closure body calls await updateFrame(), capturing self strongly. The task loops over an AsyncTimerSequence that never terminates on its own, so the task keeps the pipeline alive indefinitely.

Consequence: deinit cannot run while playback is active, which means the updateTask?.cancel() and player?.pause() calls in deinit are unreachable in exactly the situation they exist for. The only way to release the pipeline is to call pause() first.

2. play() overwrites updateTask without cancelling the previous one.

Calling play() a second time (e.g. after a play/play sequence with no intervening pause) drops the existing task handle on the floor. The old task is never cancelled and keeps running its 16 ms loop, so each redundant play() adds another concurrent frame-update loop, all writing currentTexture.

Repro for (2):
1. Create a VideoTexturePipeline and loadVideo(url:).
2. Call play() twice.
3. Call pause() once.

Expected: no frame-update loops remain running.
Actual: one loop from the first play() is still running; pause() only cancelled the second.

---

## 33: FontAtlasCache is marked Sendable but shares mutable, non-thread-safe atlas objects

+++
status: closed
priority: high
kind: bug
labels: concurrency, effort:s
created: 2026-08-09T00:09:19Z
updated: 2026-08-09T00:18:52Z
closed: 2026-08-09T00:18:52Z
+++

FontAtlasCache (Sources/MetalSprocketsAddOns/Slug/SlugTextMeshBuilder.swift) is declared @unchecked Sendable, but its stored cache is [String: SlugFontAtlas] and SlugFontAtlas is a mutable class with no internal synchronization.

SlugFontAtlas exposes insertGlyphs(_:), which mutates atlas state and reallocates its curveTexture / bandTexture. Nothing guards those mutations.

The documented purpose of FontAtlasCache is to hand the same SlugFontAtlas instances to a second SlugTextMeshBuilder (via init(device:fontAtlasCache:)) so glyphs are not re-rasterized. Declaring the container Sendable asserts that this handoff is safe across isolation domains, which is not true: two builders constructed from the same cache and driven from different threads will race inside insertGlyphs and on texture reallocation.

Note that SlugTextMeshBuilder itself is correctly not Sendable, so the Sendable conformance on the cache is the only thing enabling the unsafe pattern.

---

## 34: SlugScene publishes an escaping mutable pointer into GPU memory while claiming Sendable

+++
status: closed
priority: medium
kind: bug
labels: concurrency, effort:s
created: 2026-08-09T00:09:27Z
updated: 2026-08-09T00:20:02Z
closed: 2026-08-09T00:20:02Z
+++

SlugScene (Sources/MetalSprocketsAddOns/Slug/SlugScene.swift) is declared @unchecked Sendable while exposing unrestricted mutable aliasing of shared GPU storage.

Two problems:

1. The modelMatrices property returns an UnsafeMutableBufferPointer<float4x4> built from modelMatricesBuffer.contents(). The pointer escapes the accessor with no lifetime relationship to the buffer that owns the memory, so nothing prevents a caller from holding it past the lifetime of the SlugScene. The neighbouring withModelMatrices(_:) already provides scoped, bounds-checked access via MutableSpan; the escaping property undermines it.

2. Combined with the Sendable conformance, the type invites concurrent writers to the same model-matrix buffer from different isolation domains. There is no synchronization.

Additionally, the Sendable claim is inaccurate on its face: fontTexturePairs is [(curveTexture: MTLTexture, bandTexture: MTLTexture)], and MTLTexture does not conform to Sendable in the current SDK (verified against MacOSX27.0.sdk — MTLDevice, MTLCommandQueue, MTLBuffer and MTLAccelerationStructure do conform; MTLTexture does not).

---

## 35: Unnecessary @unchecked Sendable and @preconcurrency imports suppress future concurrency checking

+++
status: closed
priority: low
kind: enhancement
labels: concurrency, cleanup, effort:xs
created: 2026-08-09T00:09:34Z
updated: 2026-08-09T00:38:28Z
closed: 2026-08-09T00:38:28Z
+++

Several concurrency escape hatches in the codebase appear to be unnecessary, and each one disables checking that would catch future regressions.

1. AccelerationStructureManager (Sources/MetalSprocketsAddOns/Pipelines/RayTracedShadows.swift) is declared @unchecked Sendable, but every stored property is already Sendable: device (MTLDevice), commandQueue (MTLCommandQueue), primitiveAccelerationStructures ([MTLAccelerationStructure]) and instanceAccelerationStructure (MTLAccelerationStructure?). The nested Instance type is Int + simd_float4x4. Verified against MacOSX27.0.sdk that all four Metal protocols conform to Sendable. The unchecked conformance therefore buys nothing and silently accepts any future non-Sendable stored property.

2. @preconcurrency import Metal appears in three Slug files: SlugScene.swift:3, SlugMetalTypes.swift:1, SlugTextMesh.swift:3. The types in those files already carry @unchecked Sendable, so the @preconcurrency attribute is likely redundant. Where it is redundant it downgrades all future Sendable-related diagnostics from the Metal module in those files to warnings, including genuine MTLTexture-crossing-isolation errors.

Both should be removed where the build still succeeds, and kept only where removal produces a real error.

\- `2026-08-09T00:38:27Z`: Investigated on Xcode 27 beta 4 / MacOSX27.0.sdk. Both escape hatches turn out to be load-bearing:

- Removing `@unchecked` from AccelerationStructureManager fails: MTLAccelerationStructure (like the other MTLResource protocols) is NOT Sendable — only MTLDevice and MTLCommandQueue are. Two errors: 'stored property ... contains non-Sendable type any MTLAccelerationStructure'.
- SlugScene.swift and SlugTextMesh.swift no longer have @preconcurrency imports. SlugMetalTypes.swift still needs it: without it, 'static property descriptor is not concurrency-safe because non-Sendable type MTLVertexDescriptor may have shared mutable state'.

Kept both, added comments explaining why so nobody re-investigates. Closing.

---

## 36: VideoTexturePipeline polls for video frames on a fixed 16ms timer

+++
status: closed
priority: medium
kind: enhancement
labels: effort:m
created: 2026-08-09T00:09:42Z
updated: 2026-08-09T00:24:32Z
closed: 2026-08-09T00:24:32Z
+++

VideoTexturePipeline.play() drives frame updates from AsyncTimerSequence(interval: .milliseconds(16), clock: .continuous), then asks videoOutput.hasNewPixelBuffer(forItemTime:) on each tick.

The 16 ms cadence is unrelated to both the display refresh rate and the video frame rate, so frames are duplicated or dropped whenever either differs from ~60 Hz. On a 120 Hz display the texture updates at half the available rate; on a 24 or 30 fps video the same frame is redundantly converted to a Metal texture multiple times; on a 60 Hz display the timer and the display will drift relative to one another.

AVPlayerItemOutput provides requestNotificationOfMediaDataChange(withAdvanceInterval:) and an associated delegate for exactly this, and CADisplayLink provides display-synchronized callbacks.

This is a rendering-quality and efficiency issue rather than a crash or race.

- `2026-08-09T00:24:32Z`: Fixed by pacing the update loop to the video's own nominal frame rate (2x the frame rate, clamped to 250 Hz max) instead of a fixed 16 ms timer. Display-link synchronisation was not adopted: CADisplayLink needs a view/screen, which this pipeline (a headless texture producer) does not have, so the caller's renderer remains the right place for display sync. AVPlayerItemOutputPullDelegate was also not adopted - hasNewPixelBuffer already gates texture creation, so it would only save timer wakeups.

---

## 37: VideoTexturePipeline tests: unbounded busy-wait can hang the suite, and play() is uncovered

+++
status: closed
priority: low
kind: bug
labels: testing, effort:s
created: 2026-08-09T00:09:49Z
updated: 2026-08-09T00:25:54Z
closed: 2026-08-09T00:25:54Z
+++

Two issues in Tests/MetalSprocketsAddOnsTests/VideoTexturePipelineTests.swift.

1. Unbounded wait (writeTestMovie, around line 93):

    while !input.isReadyForMoreMediaData {
        try await Task.sleep(nanoseconds: 1_000_000)
    }

If AVAssetWriterInput never reports ready (writer failure, codec unavailable on the CI GPU), this loop never exits and the test suite hangs rather than failing with a diagnostic. There is no iteration cap and no check of writer.status inside the loop.

Minor: the deprecated-style Task.sleep(nanoseconds:) is used rather than Task.sleep(for:).

2. No coverage of play().

The suite covers init, loadVideo and pause, but never calls play(). The task-lifetime defects described in the play() leak issue (retain cycle preventing deinit, and a second play() orphaning the first update loop) are both reachable from a test that calls play() twice and then asserts teardown, but nothing currently exercises that path.

---

## 38: makeTextureCubeFromCrossTexture is @MainActor despite doing no main-thread work

+++
status: closed
priority: low
kind: enhancement
labels: concurrency, effort:xs
created: 2026-08-09T00:09:56Z
updated: 2026-08-09T00:20:06Z
closed: 2026-08-09T00:20:06Z
+++

MTLDevice.makeTextureCubeFromCrossTexture(texture:) in Sources/MetalSprocketsAddOns/Support/MTLDevice+TextureUtilities.swift is annotated @MainActor, but its body is a pure GPU blit: it builds an MTLTextureDescriptor, creates a cube map, and runs a BlitPass copying six faces.

Nothing in it requires the main actor. By contrast the neighbouring makeTexture(content:) genuinely needs @MainActor because it uses SwiftUI ImageRenderer.

My guess is that the annotation exists to make the non-Sendable MTLTexture parameter and return value typecheck rather than as a deliberate isolation decision, but I have not confirmed what BlitPass.run() requires.

Effect: callers are forced onto the main thread to perform what can be a large GPU copy, and callers already off the main actor must hop for no reason.

---

## 39: Matrix conventions differ between pipelines with no shared transform type

+++
status: closed
priority: medium
kind: enhancement
labels: architecture, testability, effort:l
created: 2026-08-09T00:11:17Z
updated: 2026-08-09T01:20:37Z
closed: 2026-08-09T01:20:37Z
+++

Each render pipeline invents its own camera/matrix convention:

- `FlatShader` takes a pre-multiplied `modelViewProjection`.
- `LambertianShader` / `LambertianShaderInstanced` take `projectionMatrix`, `cameraMatrix`, `modelMatrix` and recompute MVP, the normal matrix, and camera position inline.
- `blinnPhongMatrices` takes `projectionMatrix`, `viewMatrix`, `modelMatrix`, `cameraMatrix` (view and camera both, unexplained).
- `GridShader` takes projection + camera and inverts internally.
- `ShadowMaskPass` and `RayTracedShadowComputePass` take an `inverseViewProjection` the caller must derive.
- `ShadowMap` builds light matrices via its own private `float4x4.lookAt` / `orthographic` helpers, including an inverse-Z variant not used anywhere else.

Consequences:

- A caller must know which convention each pipeline chose; there is no shared vocabulary for projection/view/model/normal/inverse-VP.
- Normal-matrix and camera-position derivation is copy-pasted across pipelines.
- Passing the wrong-but-well-formed matrix produces a plausible image, so golden-image tests do not reliably catch it.
- Tests re-implement the same camera setup helpers (`perspectiveProjection`, `lookAtOriginCameraMatrix`) separately from the library.

The transform math is pure and in-process, but it is currently only tested indirectly through golden images, apart from two `lookAt`/`orthographic` tests in `ShadowMapTests`.

---

## 40: Shadow rendering chain is uncovered by tests and hand-wired by callers

+++
status: closed
priority: high
kind: enhancement
labels: architecture, testability, effort:xl, has-subtasks
depends: 45, 46, 47, 48, 49
created: 2026-08-09T00:11:30Z
updated: 2026-08-09T02:25:24Z
closed: 2026-08-09T02:25:24Z
+++

The shadow subsystem is spread across `ShadowMap`, `ShadowMapDepthPass`, `ShadowMaskPass`, `AccelerationStructureManager`, and `RayTracedShadowComputePass`, with no shared entry point.

What's wrong:

- Two techniques (shadow maps, ray-traced shadows) solve the same problem with completely different call protocols. A caller must know pass ordering, which textures to allocate with which usage flags, how to derive `inverseViewProjection`, how per-light matrices are updated, and which resources need `useResource` calls (acceleration structures, light buffers).
- `ShadowMapTests` states the end-to-end path cannot be tested: nesting a `RenderPass` per light inside `ShadowMapDepthPass` triggers 'A command encoder is already encoding to this command buffer' in `OffscreenRenderer`. Verbatim note in the test file:

      // NOTE: An end-to-end ShadowMapDepthPass + ShadowMaskPass render test was attempted
      // but triggers a Metal command-buffer assertion ("A command encoder is already encoding
      // to this command buffer") inside OffscreenRenderer when the depth pass nests its own
      // RenderPass per light. Until OffscreenRenderer can host nested render passes, the
      // shadow render-pipeline code paths remain uncovered. Tracked separately.

\- `2026-08-09T00:11:30Z`: As a result the only shadow-map coverage is struct getters (`resolution`, `lightCount`, texture descriptors) and the two matrix helpers. The actual rendering — bias sign flips for inverse Z, slice-per-light render pass descriptors, blend setup in the mask pass, depth reconstruction — has no tests.
\- `2026-08-09T00:11:30Z`: Ray-traced shadows do have a golden test, but only because its test hand-assembles the whole scene graph (~120 lines) including the exact texture usage flags the pass requires.
\- `2026-08-09T00:13:48Z`: Related: #22 — the OffscreenRenderer nested render pass limitation is tracked there and blocks end-to-end shadow tests.
\- `2026-08-09T02:06:35Z`: Split into subtasks (#22 is fixed, so the end-to-end test now exists and that part of this issue is stale):

- #45 — extract a shared shadow test scene fixture (effort:s)
- #46 — unit-test the inverse-Z contract: bias signs, sampler, clear depth, per-light slices (effort:s)
- #47 — test shadow mask correctness per pixel, depends on #45 (effort:m)
- #48 — shared shadow entry point for shadow-mapped shadows (effort:m)
- #49 — same entry point for ray-traced shadows, depends on #48 (effort:m)

Keeping this open as a tracking issue.

- `2026-08-09T02:25:21Z`: All subtasks (#45–#49) are done: shared test fixture, inverse-Z contract tests, per-pixel shadow mask tests, and the ShadowTechnique entry point with shadow-mapped and ray-traced conformances.

---

## 41: Slug text pipeline requires public access to SlugScene GPU internals

+++
status: closed
priority: medium
kind: enhancement
labels: architecture, testability, effort:l
created: 2026-08-09T00:11:42Z
updated: 2026-08-09T00:22:59Z
closed: 2026-08-09T00:22:59Z
+++

The Slug cluster (`SlugTextMeshBuilder`, `SlugFontAtlas`, `SlugScene`, `SlugTextMesh`/`SlugBufferStorage`, `SlugTextRenderPipeline`, `FontAtlasCache`) has no boundary that hides its GPU representation.

What's wrong:

- `SlugScene` publicly exposes `bufferStorage`, `fontTexturePairs`, `modelMatricesBuffer`, `totalIndexCount`, and an `UnsafeMutableBufferPointer` view of the model matrices. These exist so `SlugTextRenderPipeline` can reach back into the scene; they are not useful to a caller who just wants text on screen.
- `SlugTextRenderPipeline.init` creates its own device via `_MTLCreateSystemDefaultDevice()` and builds the font-texture argument buffer itself, duplicating knowledge of the ordering that `SlugTextMeshBuilder` established in `orderedFontNames`/`fontIndexMap`.
- The builder/scene/pipeline triple shares undocumented invariants: font index ordering must match the texture pair array, one model matrix per mesh, `finalize()` may be called exactly once, `buildMesh` is illegal after finalize (enforced only by `precondition`).
- `SlugTextMeshBuilderTests` is 473 lines and asserts largely on internal offsets, index counts and buffer layout, so it pins the current representation rather than the rendering behaviour. Only two golden tests exercise the actual pipeline.
- Two nearly identical vertex-emission loops exist (`buildMesh(attributedString:)` and `buildMesh(characters:font:cellSize:columns:)`), each recomputing glyph margin, band packing, and inverse Jacobian.

---

## 42: Argument-buffer packing and useResource calls are hand-paired per type

+++
status: closed
priority: medium
kind: enhancement
labels: architecture, effort:l
created: 2026-08-09T00:11:52Z
updated: 2026-08-09T00:42:37Z
closed: 2026-08-09T00:42:37Z
+++

`ColorSource`, `BlinnPhongMaterial`, and `Lighting` each hand-roll a `toArgumentBuffer()` plus a separate, manually written set of `useResource` calls that must list exactly the resources referenced by that argument buffer. Nothing ties the two halves together, so they can drift silently and the GPU reads unbound resources.

Evidence in the code:

- `ColorSource.swift`: TODO comment — "We may want some kind of `argumentBufferRepresentable` protocol. Should also support `useResource`"
- `ColorSource.swift`: `// TODO: This is duplicated with MetalSprocketsExampleShaders!`
- `Element.useResource(_ color: ColorSource, ...)` has the `textureCube` and `depth2D` cases commented out with the note that they cause hangs on iOS/macOS with argument buffers, so those color source cases are silently unbound.
- `FlatShader` bypasses that helper and writes the three `useResource` calls inline; `blinnPhongMaterial` writes three more; `RayTracedShadowComputePass` writes its own for the light buffers and acceleration structures.
- `ColorSourceTests` asserts on argument-buffer struct fields rather than on whether a bound resource is actually sampled correctly, so the missing `useResource` cases are not caught.

Note: some of this may belong upstream in MetalSprockets rather than in this package.

---

## 43: SlugTextMeshBuilderTests pins buffer layout instead of behaviour

+++
status: closed
priority: low
kind: task
labels: testing, effort:m
created: 2026-08-09T00:22:50Z
updated: 2026-08-09T02:46:04Z
closed: 2026-08-09T02:46:04Z
+++

SlugTextMeshBuilderTests is ~500 lines and asserts largely on internal vertex/index offsets and buffer layout, so the tests must be rewritten whenever the GPU representation changes.

Follow-up to #41, which hid the GPU internals behind the public API but left the test suite as-is (it reaches in via @testable).

Suggested direction:
- Keep a small number of layout tests as explicit representation tests, clearly marked.
- Express the rest in terms of observable behaviour: mesh count, index count, bounds, and golden renders.
- Add golden coverage for the fixed-grid buildMesh(characters:font:cellSize:columns:) path, which currently has no rendering test.

---

## 44: Texture sampling returns constant values on GitHub Actions paravirt GPU

+++
status: blocked
priority: medium
kind: bug
labels: testing, ci, effort:m, blocked, upstream
created: 2026-08-09T00:39:50Z
updated: 2026-08-09T02:35:54Z
+++

Five golden-image tests are gated off on GitHub Actions runners because `texture.sample(...)` returns a constant instead of texel data (plain rgba8Unorm -> white, YCbCr two-plane -> green). Geometry renders correctly; only sampling is wrong. Local Apple silicon and a local VirtualBuddy paravirt VM both sample correctly, so this looks specific to the GitHub Actions runner image's paravirt driver.

Affected tests (currently disabled via the `CI` env var):
- FlatShaderTests.testFlatShaderWithTexture
- TextureBillboardPipelineTests.testTextureBillboardPipeline_checkerboard
- TextureBillboardPipelineTests.testTextureBillboardPipeline_upperRightQuadrant
- TexturedQuad3DPipelineTests.testTexturedQuad3DPipeline_mandrillFlat
- TexturedQuad3DPipelineTests.testTexturedQuad3DPipeline_mandrillRotatedInPerspective

Split out of #29, which covered the mesh-shader encoder crash (now fixed).

Next steps: replace the env-var gate with a runtime probe (render a quad sampling a known texture, compare against expected texel), or re-enable once GitHub rolls a newer runner image.

- `2026-08-09T02:35:54Z`: Blocked on the GitHub Actions runner image: only the paravirt driver can fix the sampling. Gate cleanup (runtime probe instead of the CI env var, plus skip messages that reference this issue rather than #29) split out to #52.

---

## 45: Extract a shared shadow test scene fixture

+++
status: closed
priority: high
kind: enhancement
labels: testing, effort:s, subtask
created: 2026-08-09T02:05:53Z
updated: 2026-08-09T02:18:56Z
closed: 2026-08-09T02:18:56Z
+++

The ray-traced shadow test and the shadow map end-to-end test each hand-assemble the same scene: a sphere above a ground plane, a camera at a slight downward angle, a single light, and an OffscreenRenderer with specific texture usage flags. Both are ~120 lines and drift independently.

Extract that scene into `Tests/MetalSprocketsAddOnsTests/Support/` as a reusable fixture: meshes and transforms, camera/view transforms, light, and a renderer configured with the usage flags the shadow passes require.

Acceptance criteria

- A single helper builds the sphere/plane scene and the correctly-configured `OffscreenRenderer`.
- `RayTracedShadowComputePassTests` and `ShadowMapTests` both use it, and their golden/luminance expectations still pass unchanged.
- Neither test file repeats the texture usage flags or the camera setup.

Part of #40.

---

## 46: Unit-test the shadow map inverse-Z contract

+++
status: closed
priority: high
kind: enhancement
labels: testing, effort:s, subtask
created: 2026-08-09T02:06:01Z
updated: 2026-08-09T02:20:20Z
closed: 2026-08-09T02:20:20Z
+++

Only the `ShadowMap` struct getters and the two matrix helpers are covered. The inverse-Z details that actually break renders have no tests: depth bias and slope scale sign flips, the sampler compare function and border colour, the clear depth value, and the per-light depth attachment slice descriptors.

These are all pure decisions made from `useInverseZ`, so they can be tested without rendering — exposing them as small internal computed properties on `ShadowMap` (or a descriptor-producing helper) is in scope.

Acceptance criteria

- Tests assert bias and slope scale are negated when `useInverseZ` is true and not otherwise.
- Tests assert the sampler compare function and border colour flip with `useInverseZ`.
- Tests assert clear depth is 0.0 for inverse Z and 1.0 for standard Z.
- Tests assert the depth attachment for light `i` targets slice `i` with `renderTargetArrayLength` 1.

Part of #40.

---

## 47: Test shadow mask correctness per pixel

+++
status: closed
priority: high
kind: enhancement
labels: testing, effort:m, subtask
depends: 45
created: 2026-08-09T02:06:08Z
updated: 2026-08-09T02:22:14Z
closed: 2026-08-09T02:22:14Z
+++

The end-to-end shadow test only checks that mean luminance drops by 3% when the mask pass is applied. That passes even if the shadow lands in the wrong place, so the depth reconstruction in the mask kernel is effectively untested.

Assert on specific pixels instead: a point on the ground plane inside the sphere-cast shadow must darken, and a point well outside it must not. Reuse the fixture from #45 for the scene.

Acceptance criteria

- Test samples at least one known shadowed pixel and one known lit pixel and asserts the expected darkening/no-change.
- Test covers `shadowIntensity` scaling the darkening.
- Test still runs under `OffscreenRenderer` without nested render passes.

Part of #40.

---

## 48: Add a shared shadow entry point for shadow-mapped shadows

+++
status: closed
priority: high
kind: enhancement
labels: architecture, effort:m, subtask
created: 2026-08-09T02:06:15Z
updated: 2026-08-09T02:24:01Z
closed: 2026-08-09T02:24:01Z
+++

There is no shared entry point for shadows: a caller wiring up shadow maps must know the pass ordering (depth pass as a sibling of the scene pass, mask pass after it), which textures to allocate with which usage flags, how to derive the inverse view-projection, and how per-light matrices are updated.

Introduce a technique abstraction (e.g. a `ShadowTechnique` protocol plus a `ShadowMapTechnique` conformance) that owns those decisions: it takes the scene `ViewTransforms`, the lights, and the target colour/depth textures, and emits the passes in the right order.

Acceptance criteria

- One type produces the full shadow-mapped chain from view transforms + lights + target textures.
- Matrices are derived from `ViewTransforms` rather than hand-computed by callers.
- Required texture usage flags are documented (and validated) in one place.
- The existing shadow map test renders through the new entry point with unchanged results.

Part of #40.

---

## 49: Implement the shadow entry point for ray-traced shadows

+++
status: closed
priority: high
kind: enhancement
labels: architecture, effort:m, subtask
depends: 48
created: 2026-08-09T02:06:24Z
updated: 2026-08-09T02:24:55Z
closed: 2026-08-09T02:24:55Z
+++

Ray-traced shadows use a completely different call protocol from shadow maps: build acceleration structures, keep the instance/primitive structures alive, issue the right `useResource` calls for the acceleration structures and light buffers, and derive the inverse view-projection.

Implement the technique abstraction from #48 for ray-traced shadows so both techniques are interchangeable behind one entry point.

Acceptance criteria

- A ray-traced conformance produces the compute pass, owning acceleration structure lifetime and `useResource` calls.
- Callers can swap between shadow-mapped and ray-traced shadows without changing pass wiring.
- `RayTracedShadowComputePassTests` renders through the entry point with its golden image unchanged.

Part of #40.

---

## 50: Mesh-shader capability probe false-positives on CI, crashing the test run

+++
status: closed
priority: high
kind: bug
labels: testing, ci, effort:s
created: 2026-08-09T02:28:59Z
updated: 2026-08-09T02:29:04Z
closed: 2026-08-09T02:29:04Z
+++

The supportsMeshShaders probe in Tests/MetalSprocketsAddOnsTests/Support/GPUCapabilities.swift asks the render command encoder whether it responds to setMeshBuffer:offset:atIndex:. On GitHub Actions the probe reported true, testGraphicsContext3D_debugWireframe ran, and the process died with 'unrecognized selector sent to AppleParavirtRenderCommandEncoder' (run 31289708570).

Likely cause: a validation/debug layer wraps the encoder, answers respondsToSelector for every protocol selector, and forwards to the real paravirt encoder, which has no mesh stage.

Fix: exclude paravirtual devices by name before probing.

---

## 51: GPU capability probes are duplicated per test target instead of living in MetalSupport

+++
status: closed
priority: medium
kind: task
labels: effort:m, area:testing
created: 2026-08-09T02:32:13Z
updated: 2026-09-30T18:42:37Z
closed: 2026-09-30T18:42:37Z
+++

Tests/MetalSprocketsAddOnsTests/Support/GPUCapabilities.swift holds runtime probes for GPU features (mesh-shader support, ray tracing, paravirtual device detection) that are not specific to this package. Any other package with golden-image or GPU tests needs the same probes and has to copy them, and each copy drifts as new CI quirks are found (see #29, #44, #50).

## Proposed fix (per user)

Move the probes into MetalSupport so they can be shared, and have this test target use them from there.

- `2026-08-09T02:43:49Z`: Punting for now: the useful probes (paravirtual detection, mesh-shader probe) can move to MetalSupport, but supportsTextureSampling renders through MetalSprockets' TextureBillboardPipeline, so it cannot live in MetalSupport as written. The move also needs a MetalSupport release plus a Package.swift bump here, i.e. commits and a tag in another repo. Unblocker: confirm you want MetalSupport changed and released, and say whether the probes belong in the main library target or a new MetalSupportTesting target.
- `2026-09-30T18:42:37Z`: Device checks (isParavirtual, supportsMetal4, supportsMeshShaders) now live in MetalSupport 1.0.6 without a Testing dependency. AddOns and Examples tests use them and keep only thin Swift Testing wrappers (.requiresMetal4). supportsTextureSampling stays local (it renders through MetalSprockets) and is tracked by #44; it can be deleted once metal4 lands.

---

## 52: Texture-sampling tests are gated by the CI env var and cite the wrong issue

+++
status: closed
priority: low
kind: task
labels: testing, ci, effort:s
created: 2026-08-09T02:36:03Z
updated: 2026-08-09T02:43:31Z
closed: 2026-08-09T02:43:31Z
+++

Five texture-sampling tests are skipped with .disabled(if: ProcessInfo.processInfo.environment["CI"] != nil):
- FlatShaderTests.testFlatShaderWithTexture
- TextureBillboardPipelineTests.testTextureBillboardPipeline_checkerboard
- TextureBillboardPipelineTests.testTextureBillboardPipeline_upperRightQuadrant
- TexturedQuad3DPipelineTests.testTexturedQuad3DPipeline_mandrillFlat
- TexturedQuad3DPipelineTests.testTexturedQuad3DPipeline_mandrillRotatedInPerspective

Two problems:

1. The gate keys off the CI environment rather than the GPU behaviour it is working around, so the tests are skipped on any CI machine even where sampling works, and run on a broken GPU outside CI.
2. Their skip messages point at #29 (the mesh-shader crash, fixed) instead of #44, which is the sampling bug.

Same applies to AccelerationStructureManagerTests.testAccelerationStructureManager_build_metalMeshes, which is also still on the env-var gate.

- `2026-08-09T02:37:00Z`: Related: #44 (the underlying sampling bug these tests are gated on) and #51 (moving the capability probes into MetalSupport).

---

## 53: Release builds can embed development-only Metal shader source

+++
status: blocked
priority: high
kind: bug
labels: area:build, effort:s, blocked
created: 2026-08-25T22:10:26Z
updated: 2026-09-30T18:44:18Z
+++

The MetalCompilerPlugin is attached to the MetalSprocketsAddOnsShaders target, but the manifest does not provide a configuration-dependent compilation condition to the plugin. MetalCompilerPlugin cannot read SwiftPM's active debug or release configuration directly. As a result, its debug metallib behavior cannot differ safely between configurations, and release products can contain development-only embedded Metal shader source. App Store validation reports ITMS-91306 for affected archives.

Expected: Debug builds retain shader debugging support. Release builds produce metallibs without embedded development-only shader source.

Actual: The plugin invocation has no target build-setting signal that distinguishes debug from release.

## Proposed fix (per user)

Update MetalCompilerPlugin to a version that supports configuration conditions. Then add this setting to every target that uses the plugin:

```swift
cSettings: [
    .define("METAL_COMPILER_PLUGIN_DEBUG", .when(configuration: .debug))
],
```

- `2026-09-30T18:44:18Z`: Tried the MetalCompilerPlugin 0.3.0 fix (METAL_COMPILER_PLUGIN_DEBUG with .when(configuration: .debug)). Correct under command-line SwiftPM, but Xcode applies the debug flags in Release too, so archives would still embed shader source. Reverted. Filed upstream as MetalCompilerPlugin #. Current state: no define, so no build embeds source (safe for archives), but Debug has no shader debug info.
- `2026-09-30T18:44:25Z`: Upstream issue: MetalCompilerPlugin #1.

---

## 54: Port to MetalSprockets Metal 4 on a metal4 branch

+++
status: closed
priority: high
kind: task
labels: area:metal4, effort:l
created: 2026-09-30T05:16:56Z
updated: 2026-09-30T18:34:16Z
closed: 2026-09-30T18:34:16Z
+++

MetalSprockets is being ported to Metal 4 on its metal4 branch (https://github.com/schwa/MetalSprockets/tree/metal4). It is a breaking change and will merge into MetalSprockets main later. AddOns depends on MetalSprockets (from: "0.1.11"), and MetalSprocketsExamples and MetalSprocketsSceneGraph follow AddOns main, so AddOns needs a matching branch before MetalSprockets merges.

Work:
- Create a metal4 bookmark/branch from main.
- On it, change the MetalSprockets dependency to .package(url: "https://github.com/schwa/MetalSprockets", branch: "metal4").
- Fix the compile errors and test failures. A rough scan found about 32 uses of APIs that changed (setVertexBytes/setFragmentTexture and other encoder calls inside Draw, drawPrimitives(type:), MTLRenderCommandEncoder/MTLComputeCommandEncoder types, BlitPass, command-buffer modifiers). Some hits may be raw Metal that does not go through MetalSprockets.

Reference: Documentation/Porting-to-Metal4.md on the MetalSprockets metal4 branch. Main changes: Draw gets an MTL4RenderCommandEncoder with pipeline and parameters already bound; pass vertex data with .vertexValues/.vertexBuffer and everything else with .parameter; BlitPass is gone (ComputeCommand in a ComputePass); commands in a pass are unordered (EncoderBarrier/QueueBarrier/.barrierAfterPass); raw encoder closures must declare every resource they touch with .useResource/.useComputeResources or the GPU may write into freed memory; removed APIs are gone, not deprecated.

Done when: the package builds for macOS, iOS and visionOS against MetalSprockets metal4; tests pass on a Metal 4 Mac with MTL_DEBUG_LAYER=1; GPU tests are skipped with a reason on devices without Metal 4 (GitHub runners have a paravirtual GPU without Metal 4, related to #44); metal4 is pushed so dependents can track it. Keep main unchanged until MetalSprockets merges metal4.

- `2026-09-30T18:34:16Z`: Done on metal4 (f0779782): builds for macOS, iOS and visionOS against MetalSprockets metal4; tests pass on a Metal 4 Mac with MTL_DEBUG_LAYER=1 (Buildkite build 6); GPU tests skip with a reason via .requiresMetal4 on GitHub Actions (run on f0779782 passed); metal4 is pushed.

---

## 55: Example demos: geometry is cut off at the ground plane

+++
status: closed
priority: high
kind: bug
labels: area:metal4, area:examples, effort:m
created: 2026-09-30T16:10:52Z
updated: 2026-09-30T16:25:49Z
closed: 2026-09-30T16:25:49Z
+++

In the MetalSprocketsAddOnsExamples app on the metal4 branch, the sphere and box in several demos are cut off where they meet the ground. Only the part above the ground plane (or grid) is drawn; the lower half is missing.

Seen in:
- Blinn-Phong: sphere and box are cut off at the grid.
- Shadow Map: sphere and box are cut off at the plane.
- Ray-Traced Shadows: sphere and box are cut off at the plane, and the cast shadow also looks wrong (a large dark ellipse under the box).

Repro:
1. Build and run MetalSprocketsAddOnsExamples (macOS) on the metal4 branch.
2. Open any of the demos above.

Expected: whole objects resting on or above the plane. Actual: objects look sunk halfway into the plane.

Not yet checked whether this also happens on main (pre-Metal 4).

Screenshots:
- ~/Library/Application Support/CleanShot/media/media_tPSVpFEW5N/Screenshot 2026-09-30 at 09.10.09@2x.png (Shadow Map)
- ~/Library/Application Support/CleanShot/media/media_8TJSJR1c49/Screenshot 2026-09-30 at 09.10.15@2x.png (Ray-Traced Shadows)
- ~/Library/Application Support/CleanShot/media/media_v5WbTIx3Zn/Screenshot 2026-09-30 at 09.10.20@2x.png (Blinn-Phong)

- `2026-09-30T16:11:50Z`: Possibly related to #57 (Debug Shading sphere missing faces): both draw MTKMesh geometry through the new MTL4 draw(_ mesh:) helper.

---

## 56: Example demos: Slug Text demo renders nothing

+++
status: closed
priority: high
kind: bug
labels: area:metal4, area:examples, effort:m
created: 2026-09-30T16:10:52Z
updated: 2026-09-30T16:25:49Z
closed: 2026-09-30T16:25:49Z
+++

In the MetalSprocketsAddOnsExamples app on the metal4 branch, the Slug Text demo shows no text.

Repro:
1. Build and run MetalSprocketsAddOnsExamples (macOS) on the metal4 branch.
2. Select "Slug Text".

Expected: rendered glyphs. Actual: nothing is drawn.

The SlugTextRenderPipeline golden-image tests pass under MTL_DEBUG_LAYER=1, so the demo setup (view, amplification, depth, blending or formats) may differ from the tests. Not yet checked whether this also happens on main.

---

## 57: Example demos: Debug Shading sphere is missing faces near the top pole

+++
status: closed
priority: medium
kind: bug
labels: area:metal4, area:examples, effort:s
created: 2026-09-30T16:11:22Z
updated: 2026-09-30T16:25:49Z
closed: 2026-09-30T16:25:49Z
+++

In the MetalSprocketsAddOnsExamples app on the metal4 branch, the Debug Shading demo sphere has a hole near the top pole: a few triangles are not drawn and the background shows through.

Repro:
1. Build and run MetalSprocketsAddOnsExamples (macOS) on the metal4 branch.
2. Select "Debug Shading", mode "Normal", Sphere on, Wireframe off.

Expected: a closed sphere. Actual: a small group of faces near the top is missing.

May be related to #55 (geometry cut off at the ground plane). Not yet checked whether this also happens on main.

Screenshot: ~/Library/Application Support/CleanShot/media/media_gHZg8nSrZ1/Screenshot 2026-09-30 at 09.10.59@2x.png

- `2026-09-30T16:11:50Z`: Possibly related to #55 (geometry cut off at the ground plane).

---

## 58: Ray-traced self-shadow edge on curved meshes is stair-stepped

+++
status: open
priority: low
kind: bug
labels: area:rendering, effort:m
created: 2026-09-30T16:34:13Z
updated: 2026-10-07T18:59:49Z
+++

With RayTracedShadowComputePass, the shadow a sphere casts on itself has a blocky, stair-stepped edge instead of following the curve. The shadow cast onto the ground looks correct.

Seen in:
- The RayTracedShadowSphere golden image (Tests/MetalSprocketsAddOnsTests/Golden Images).
- The Ray-Traced Shadows demo in MetalSprocketsAddOnsExamples.

This was hidden until the instance-transform fix: before it, every instance sat at the origin, so the sphere did not shadow itself where it was drawn.

Cause not investigated. My guess is self-intersection of shadow rays with the flat triangles of the tessellated sphere, since the origin is reconstructed from the depth buffer and offset by a distance-scaled bias.

- `2026-09-30T17:11:35Z`: Diagnosed: the steps are the sphere's triangles (the shadow-terminator problem). A 192-segment sphere gives proportionally smaller steps than 48. The kernel only has depth, so a pixel on a triangle facing away from the light casts a ray that hits the far side of its own mesh. FlatShader has no N·L falloff, so the ray-traced pass alone defines the edge and the steps show. Mitigated in the Ray-Traced Shadows demo by using a 192-segment sphere. A real fix needs smooth normals in the shadow pass (skip pixels facing away from the light, offset ray origins along the normal), which means a normal texture in ShadowContext.

---

## 59: Examples demos have no rendering tests

+++
status: closed
priority: medium
kind: task
labels: area:examples, area:testing
created: 2026-09-30T16:34:13Z
updated: 2026-09-30T17:24:08Z
closed: 2026-09-30T17:24:08Z
+++

Only the package unit tests run. Nothing checks that the MetalSprocketsAddOnsExamples demos render correctly, and CI may not build the Examples app at all.

Four demo bugs were only found by looking at the running app: geometry cut by a vertical ground plane (#55), a hole in the Debug Shading sphere (#57), Slug text clipped by the far plane (#56), and animations frozen by Float time precision. A ray-traced shadow transform bug in the library was also only visible in the demo, because its golden image had been recorded with the bug.

---

## 60: RayTracedShadowComputePass still packs the acceleration structure into its parameter struct

+++
status: open
priority: low
kind: task
labels: area:rendering, area:metal4, effort:s
created: 2026-09-30T18:49:31Z
updated: 2026-10-07T18:59:49Z
+++

During the Metal 4 port, MetalSprockets could not bind acceleration structures as shader parameters, so the instance acceleration structure was moved into `RayTracedShadowParameters` as an `MTLResourceID` (RayTracedShadows.h, RayTracedShadows.metal, RayTracedShadows.swift) instead of a `[[buffer(0)]]` kernel argument.

MetalSprockets metal4 now supports `.parameter(_:accelerationStructure:)` (MetalSprockets #452), so the struct field and the kernel change are no longer needed.

---

## 61: GaussianBlurPipeline uses a custom kernel; MPS may work again on Metal 4

+++
status: open
priority: low
kind: task
labels: area:metal4, effort:s
created: 2026-09-30T18:49:31Z
updated: 2026-10-07T18:59:49Z
+++

During the Metal 4 port, MetalSprockets had no way to encode MPS work, so GaussianBlurPipeline was rewritten from MPSImageGaussianBlur to a custom two-pass separable compute kernel (GaussianBlur.metal), and its edgeMode changed from MPSImageEdgeMode to its own enum.

MetalSprockets metal4 now documents which MPS kernels work on Metal 4 (MetalSprockets #451). It is not known yet whether MPSImageGaussianBlur is one of them.

---

## 62: ShadowTestScene ground plane is vertical

+++
status: open
priority: low
kind: bug
labels: area:testing, effort:s
created: 2026-09-30T18:49:31Z
updated: 2026-10-07T18:59:49Z
+++

Tests/MetalSprocketsAddOnsTests/Support/ShadowTestScene.swift builds the ground with `MTKMesh.plane(width:height:)` and only translates it to y = -1. MTKMesh.plane lies in the XY plane, so the "ground" is a vertical wall at z = 0, not a floor. This is the same mistake fixed in the Examples demos in #55.

The shadow-map and ray-traced shadow tests and their golden images (for example RayTracedShadowSphere) render this scene, so they do not test shadows cast onto a floor.

---

## 63: Lighting writes GPU-visible buffers in place while frames are in flight

+++
status: open
priority: high
kind: bug
labels: area:metal4, effort:m
created: 2026-10-02T22:34:29Z
updated: 2026-10-07T18:59:49Z
+++

Lighting.setLightPosition(_:at:) and setLight(_:at:) write through lights.contents() and lightPositions.contents() into shared MTLBuffers. Callers animate lights every frame. Examples: RayTracedShadow, ShadowMap, BlinnPhong, and PBR via LightingAnimator. Up to maximumInFlightSubmissions (default 3) earlier frames may still read those buffers, so this is a CPU/GPU race: lights can jitter or tear. Fix options: a ring of buffers sized to frames in flight, copy-on-write per frame, or pass the light data as parameter values. Reported from MetalSprocketsExamples #439.

- `2026-10-07T18:59:50Z`: Related: #66 fixed the same in-flight buffer rewrite pattern in GraphicsContext3DRenderPipeline (fresh buffers per regeneration, uniforms via parameter values).

---

## 64: VideoTexturePipeline releases the CVMetalTexture before the GPU is done

+++
status: open
priority: high
kind: bug
labels: area:metal4, effort:s
created: 2026-10-02T22:34:29Z
updated: 2026-10-07T18:59:49Z
+++

VideoTexturePipeline.updateFrame keeps only CVMetalTextureGetTexture(cvTexture) in currentTexture. The CVMetalTexture is a local and is released right away. The CVMetalTextureCache can then recycle the backing IOSurface while in-flight frames still sample the MTLTexture. Keep the CVMetalTexture (or CVPixelBuffer) alive with the frame, and expose it as an owner so callers can retain it until completion, like YCbCrBillboardRenderPass(owners:). Affects VideoPlayback and AppleEventLogo in MetalSprocketsExamples (#439).

---

## 65: ShadowMapDepthPass needs a WAR barrier before rewriting the shadow map

+++
status: open
priority: medium
kind: bug
labels: area:metal4, effort:s
created: 2026-10-02T22:34:29Z
updated: 2026-10-07T18:59:49Z
+++

Each depth RenderPass in ShadowMapDepthPass ends with barrierAfterPass(after: .fragment, beforeQueueStages: [.vertex, .fragment, .dispatch]), but nothing orders it after earlier readers. The next frame can clear and rewrite the shadow map while the previous frame's main pass (fragment) and ShadowMaskPass (dispatch) still sample it. Add QueueBarrier(after: [.dispatch, .fragment], before: .fragment) at the start of each depth RenderPass. Callers cannot add it from outside, because a QueueBarrier only gates its own encoder. Reported from MetalSprocketsExamples #439.

---

## 66: GraphicsContext3DRenderPipeline regenerates all geometry whenever the camera moves

+++
status: closed
priority: medium
kind: enhancement
labels: performance
created: 2026-10-07T18:40:28Z
updated: 2026-10-07T18:53:24Z
closed: 2026-10-07T18:53:24Z
+++

`GraphicsContext3DRenderPipeline` regenerates all geometry when `previousContext != context`, `previousViewProjection != viewProjection`, or `previousViewport != viewport`. In apps where the camera moves every frame (AR, orbit cameras), this rebuilds all stroke join data on the CPU every frame, even when the context did not change.

Only part of that work depends on the view-projection matrix or viewport:
- Curve tessellation (`estimateQuadCurveScreenLength` / `estimateCubicCurveScreenLength` pick the segment count from screen length).
- Fill geometry.
- The `LineJoinUniforms` buffer, which holds `viewProjection` and `viewport` for the mesh shader.

Stroke join data (`LineJoinGPUData`) is in world space and `generateJoinDataForSubpath` does not read `viewProjection`; the mesh shader does the projection. For straight-line strokes, only the uniforms change per frame.

Related: the join data, fill vertex and uniforms buffers are single shared `@MSState` buffers that are rewritten in place during `body`, so a rewrite can happen while a previous frame's GPU work still reads them.

Seen in ARSprockets (~/Projects/Scratch/ARSprockets), which strokes ARKit plane outlines with a camera that moves every frame.

---

## 67: GraphicsContext3D strokes fly off screen when a segment crosses behind the camera

+++
status: closed
priority: high
kind: bug
labels: rendering
created: 2026-10-07T18:46:20Z
updated: 2026-10-07T18:53:25Z
closed: 2026-10-07T18:53:25Z
+++

Stroked paths drawn with `GraphicsContext3DRenderPipeline` produce long lines shooting across the screen when part of the path is behind the camera.

In `GraphicsContext3DShaders.metal`, `toScreen` divides clip-space xy by `clipPos.w` with no near-plane clipping. For a point behind the camera, `w` is negative, so the projected point is mirrored to the other side of the screen; points close to the camera plane project to very large coordinates. The mesh shader then emits every vertex with `w = 1` (`float4(toClip(...), 1.0)`), so the rasterizer cannot clip the triangles against the near plane.

`toScreen` only guards `abs(clipPos.w) < 1e-6`, which returns (0, 0) and also produces wrong geometry.

Seen in ARSprockets (~/Projects/Scratch/ARSprockets) stroking ARKit plane outlines. The user stands inside the room, so floor and wall outlines often pass behind the camera.

---

## 68: No reusable point cloud render pass

+++
status: open
priority: medium
kind: feature
labels: area:rendering, area:performance, effort:xl
created: 2026-10-07T18:55:34Z
updated: 2026-10-07T18:59:49Z
+++

MetalSprocketsAddOns has no shared element for drawing large point clouds. Consumers (ARSprockets, SceneGraph, GaussianSplats tooling, the PointCloudDemo in MetalSprocketsExamples) have to write their own, and point-primitive rasterization does not scale to tens or hundreds of millions of points.

Reference: Schütz, Kerbl, Wimmer, "Rendering Point Clouds with Compute Shaders and Vertex Order Optimization" (2021), https://arxiv.org/abs/2104.07526. The paper renders points with compute shaders: each point is projected and written to a 64-bit framebuffer with an atomic min of packed depth+color, then resolved to the color target. It also covers batching, vertex-order optimization (e.g. Morton order / shuffled order) for coherent access, and a high-quality mode that blends overlapping points.

Wanted:
- A reusable element (compute rasterize + resolve) that other packages can drop into a render graph, composing with depth from other passes.
- A demo in MetalSprocketsAddOnsExamples with a large point cloud and controls for the paper's variants.
- Tests, including a golden image.

Open question: can consumers supply their own code? For example, custom per-point shading/color, point attribute layout, culling or LOD, or splat size, via user shader functions (function constants, visible/linked functions, or stitched functions) instead of forking the pass.

\- `2026-10-07T18:56:57Z`: Proposed approach for consumer-supplied code (per schwa): visible functions. Consumers write a Metal function (e.g. `float4 shadePoint(PointData, ...)`) that is linked into the compute rasterizer, so they can customize per-point shading/attributes without forking the pass. Needs to fit the MetalSprockets shader-library model.

Alternatives to consider: dynamic libraries (MTLDynamicLibrary) linked into the kernel; stitched functions (MTLFunctionStitchingGraph) for graph-built shading.

---
