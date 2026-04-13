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

Fill geometry in GraphicsContext3D renders as solid white regardless of the color passed to ctx.fill(). Strokes render correctly with the right colors. The fill vertex buffer data appears to not carry color values to the shader. Visible in the GraphicsContext3D demo: star fill should be yellow, square fill should be teal — both render white. Likely a buffer binding or data copy issue in GraphicsContext3DRenderPipeline.

---

