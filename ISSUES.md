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
status: new
priority: medium
kind: bug
created: 2026-04-13T05:04:24Z

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
status: new
priority: high
kind: bug
created: 2026-04-13T17:21:37Z

GraphicsContext3D content is completely invisible on initial load. Requires a window resize to trigger rendering. Affects both the standalone GraphicsContext3D demo and the BlinnPhong demo light marker. Possibly related to #3 (wrong size/aspect on initial load) but this is a complete rendering failure, not just wrong aspect.

---

## 8: Shadow map (rasterization-based) shadows
status: new
priority: medium
kind: feature
created: 2026-04-13T17:48:11Z

Add shadow mapping support using a traditional rasterization approach. Render depth from the light's POV into a shadow map texture, then sample it in the fragment shader to determine shadow visibility. This avoids ray tracing entirely and can reuse existing pipeline patterns. Integrates with the existing Lighting and BlinnPhong infrastructure.

---

## 9: Ray traced shadows
status: new
priority: medium
kind: feature
created: 2026-04-13T17:48:18Z

Add ray traced shadow support using Metal ray tracing APIs. Build MTLPrimitiveAccelerationStructure from meshes and MTLInstanceAccelerationStructure for the scene. Cast shadow rays in the fragment shader against the acceleration structure to determine visibility. Provides higher quality shadows than shadow maps (no aliasing, no acne, correct for all geometry). Requires new MetalSprockets Element wrappers for acceleration structure management and resource binding.

---

## 10: Shadow map: fix shadow acne / self-shadowing on teapot surfaces
status: new
priority: high
kind: bug
created: 2026-04-13T18:47:31Z

With shadow debug enabled, teapot surfaces facing the light show as magenta (shadowed) due to self-shadowing artifacts. The bias direction in sample_compare needs to be corrected — subtracting bias makes it worse, adding bias breaks shadows entirely. Need to investigate proper bias strategy (e.g., slope-scale bias or receiver-plane bias).

---

## 11: Shadow map: decouple shadow sampling from Blinn-Phong shader
status: new
priority: medium
kind: feature
created: 2026-04-13T18:47:37Z

Shadow mapping is currently baked into the Blinn-Phong fragment shader via the SHADOW_MAP_ENABLED function constant. It should be factored out into a composable pass or modifier so it can work with any lighting model (e.g., FlatShader or custom shaders).

---

## 12: Shadow map: sample_compare logic may be inverted
status: new
priority: high
kind: bug
created: 2026-04-13T18:47:44Z

The comparison sampler uses .lessEqual and sample_compare returns 1.0 when storedDepth <= compareDepth. The current logic treats 1.0 as lit, but the teapots appear mostly magenta (shadowed) on light-facing surfaces. The comparison direction or the interpretation of the result may need to be inverted. Related to shadow acne issue #10.

---

## 13: Shadow map demo: floor is too dark
status: new
priority: medium
kind: bug
created: 2026-04-13T18:47:51Z

Even with ambient light bumped to [0.3, 0.3, 0.35] and light intensity at 150, the ground plane appears too dark. The quadratic attenuation in the Blinn-Phong shader (1.0 / (1.0 + 0.09*d² + 0.032*d⁴)) heavily attenuates at the orbit distance (~7 units). Consider making attenuation configurable or using a less aggressive falloff.

---

