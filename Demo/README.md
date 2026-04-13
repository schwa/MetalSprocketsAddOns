# MetalSprocketsAddOns Demo

A demo app showcasing MetalSprocketsAddOns features. Built with [DemoKit](https://github.com/schwa/DemoKit) for demo navigation and [Interaction3D](https://github.com/schwa/Interaction3D) for camera controls.

## Platforms

- **macOS** — DemoKit sidebar with all demos
- **iOS/iPadOS** — DemoKit sidebar + ARKit camera passthrough mode
- **visionOS** — Tab-based UI with immersive space support

## Demos

| Demo | Features Shown |
|---|---|
| **Spinning Cube** | `RenderView`, `RenderPipeline`, `Draw`, MSAA controls, screenshots |
| **Infinite Grid** | `GridShader` (Pristine Grid), highlighted axis lines, major/minor subdivision, inspector UI |
| **Graphics Context 3D** | `GraphicsContext3D`, `Path3D`, stroked/filled paths, `SlugTextRenderPipeline` for 3D labels, `SwiftEarcut` triangulation |
| **Slug Debug** | Basic `SlugTextMeshBuilder` + `SlugTextRenderPipeline` |
| **Text Panel** | Multi-language/multi-font Slug text, wireframe toggle |
| **Spinning Sphere** | Instanced Slug text on orbital paths |
| **Matrix Rain** | High-volume Slug text animation with orthographic projection |
| **Terminal** | Live process output with ANSI color parsing, `FontAtlasCache` reuse (macOS only) |
| **Immersive Matrix Rain** | visionOS immersive space, stereo rendering via vertex amplification (visionOS only) |

## Dependencies

- [MetalSprockets](https://github.com/schwa/MetalSprockets) / MetalSprocketsUI — rendering framework and SwiftUI integration
- [MetalSprocketsAddOns](../) — the library being demoed
- [DemoKit](https://github.com/schwa/DemoKit) — demo navigation and configuration UI
- [Interaction3D](https://github.com/schwa/Interaction3D) — turntable/arcball camera controls
