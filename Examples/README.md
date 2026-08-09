# Examples

`MetalSprocketsAddOnsExamples` is a multiplatform SwiftUI app that exercises the harder parts
of MetalSprocketsAddOns interactively. The package itself is consumed as a local path
dependency, so edits to `Sources/MetalSprocketsAddOns` show up on the next build.

```bash
cd Examples/MetalSprocketsAddOnsExamples
xcb build -S
xcb run -S
```

Every demo lives in `Packages/MetalSprocketsAddOnsExamplesSupport`. The app target is a thin
shell around `DemoBrowserView`.

## Demos

| Demo | What it shows |
| --- | --- |
| Blinn-Phong | `Lighting` and `BlinnPhongMaterial` argument buffers, with lights mutated in place per frame. |
| Shadow Map | The three-pass chain: `ShadowMapDepthPass` → scene → compute `ShadowMaskPass`. |
| Ray-Traced Shadows | `AccelerationStructureManager` plus `RayTracedShadowComputePass`. |
| GraphicsContext3D | `Path3D` stroking and filling with screen-space line widths, caps and joins. |
| Slug Text | `SlugTextMeshBuilder` / `SlugTextRenderPipeline` resolution-independent glyphs. |
| Debug Shading | `DebugRenderPipeline`'s per-attribute visualisations. |

## Things worth knowing

- The shadow demos need a readable depth attachment and a writable drawable, hence
  `.metalDepthStencilAttachmentTextureUsage([.renderTarget, .shaderRead])` and
  `.metalFramebufferOnly(false)` on their `RenderView`.
- `ShadowMapDepthPass`, `ShadowMaskPass` and `RayTracedShadowComputePass` each open their own
  command encoder, so they must be siblings of the scene's `RenderPass`, never nested inside it.
- The debug-shading demo builds its mesh with an explicit interleaved tangent-basis layout.
  Model I/O otherwise spreads attributes across several vertex buffers, which collides with the
  uniform buffer indices the shaders use.
- Ray tracing is unavailable on some GPUs (including CI's paravirtualised one); that demo
  degrades to a `ContentUnavailableView`.
