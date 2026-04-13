# MetalSprocketsAddOns

Higher-level rendering pipelines, mesh utilities, GPU text rendering, and shaders built on top of [MetalSprockets](https://github.com/schwa/MetalSprockets).

## Targets

### MetalSprocketsAddOns

Ready-to-use MetalSprockets `Element` pipelines, mesh types, and GPU text rendering.

**Render Pipelines:**

| Pipeline | Description |
|---|---|
| `FlatShader` | Unlit textured/colored mesh rendering with configurable `ColorSource` |
| `LambertianShader` | Simple diffuse lighting with a directional light |
| `GridShader` | Infinite ground-plane grid using the [Pristine Grid](https://bgolus.medium.com/the-best-darn-grid-shader-yet-727f9278b9d8) algorithm with highlighted lines and major/minor subdivision |
| `WireframeRenderPipeline` | Triangle-fill-mode wireframe for `MTKMesh` |
| `EdgeLinesRenderPipeline` | Mesh-shader edge rendering with configurable line width (extracts unique edges) |
| `AxisLinesRenderPipeline` | Colored X/Y/Z axis lines with screen-space line width |
| `AxisAlignedWireframeBoxesRenderPipeline` | Instanced wireframe AABB boxes |
| `TextureBillboardPipeline` | Full-screen texture billboard with stitched color-transform functions |
| `TexturedQuad3DPipeline` | YCbCr-textured quad positioned in 3D world space |
| `GraphicsContext3DRenderPipeline` | Canvas-style 3D path stroking/filling with pixel-perfect line widths, caps, and joins |
| `SlugTextRenderPipeline` | GPU text rendering using the Slug algorithm with per-glyph curve/band textures |

**Mesh Types:**

| Type | Description |
|---|---|
| `TrivialMesh` | CPU-side mesh with positions, normals, tangents, UVs, colors, and indices |
| `Mesh` | GPU-backed mesh with `MTLBuffer` vertex/index buffers and a `VertexDescriptor` |
| `MeshWithEdges` | Mesh + extracted unique edge list for edge rendering |

`TrivialMesh` includes shape generators (box, sphere, cylinder, cone, torus, plane), tangent generation via MikkTSpace, and conversion to GPU `Mesh`.

**Slug Text Rendering:**

| Type | Description |
|---|---|
| `SlugTextMeshBuilder` | Builds text meshes from attributed strings, with shared vertex/index buffers |
| `SlugScene` | Bundles all GPU resources (buffers, textures, model matrices) for rendering |
| `SlugTextRenderPipeline` | MetalSprockets `Element` for rendering Slug text scenes, with stereo/amplification support |
| `FontAtlasCache` | Reusable font atlas cache to avoid re-rasterizing glyphs across rebuilds |

Supports CoreText attributed strings with per-run colors and fonts, monospace grid layout for terminal-style rendering, and visionOS stereo rendering via vertex amplification.

**Other:**

- `GraphicsContext3D` / `Path3D` — SwiftUI `Canvas`-style API for recording stroke/fill commands on 3D paths (lines, quadratic/cubic curves, subpaths)
- `ColorSource` — enum wrapping texture2D, textureCube, depth2D, or solid color for shader parameterization
- `SimpleStitchedFunctionGraph` — helper for building Metal stitched function pipelines

### MetalSprocketsAddOnsShaders

Metal shaders (compiled via MetalCompilerPlugin) for all the pipelines above. Includes axis lines, boxes, edge rendering, flat/grid/lambertian/wireframe shaders, texture billboard, textured quad 3D, GraphicsContext3D mesh/object shaders, and Slug text rendering shaders.

### MikkTSpace

Bundled C implementation of [MikkTSpace](http://www.mikktspace.com/) for tangent-space generation.

## Demo App

The `Demo/` directory contains a macOS/iOS/visionOS demo app built with [DemoKit](https://github.com/schwa/DemoKit) and [Interaction3D](https://github.com/schwa/Interaction3D).

**Demos:**

| Demo | Description |
|---|---|
| Spinning Cube | RGB gradient cube with MSAA controls |
| Infinite Grid | Pristine grid shader with highlighted axis lines, major/minor subdivision, and inspector controls |
| Graphics Context 3D | Stroked/filled 3D paths (star, triangle, zigzag, cube, pyramid, spiral, arrow, cross, L-shape) with Slug text labels |
| Slug Debug | Basic Slug text rendering test |
| Text Panel | Multi-language text rendered with Slug |
| Spinning Sphere | "Hello World" in 28 languages orbiting a sphere |
| Matrix Rain | Falling katakana/digits animation |
| Terminal | Live terminal output with ANSI color parsing (macOS only) |
| Immersive Matrix Rain | visionOS immersive space with cylindrical character rain |

## Dependencies

- [MetalSprockets](https://github.com/schwa/MetalSprockets) — declarative Metal rendering framework
- [MetalCompilerPlugin](https://github.com/schwa/MetalCompilerPlugin) — Swift Package Manager plugin for compiling Metal shaders
- [GeometryLite3D](https://github.com/schwa/GeometryLite3D) — lightweight 3D geometry types
- [SwiftEarcut](https://github.com/schwa/SwiftEarcut) — polygon triangulation (earcut algorithm)
- [swift-collections](https://github.com/apple/swift-collections) — Swift Collections

## Overlap with MetalSprockets

MetalSprockets core provides the rendering framework (Element tree, RenderPass, RenderPipeline, MeshRenderPipeline, Draw, etc.) but includes very few concrete shaders. Two areas of partial overlap:

- **YCbCr Billboard:** MetalSprockets has `YCbCrBillboardRenderPass` (in MetalSprocketsUI) for full-screen YCbCr camera/video backgrounds. This package has `TexturedQuad3DPipeline` which also renders YCbCr textures but on a 3D-positioned quad, and `TextureBillboardPipeline` which is a more general billboard with dual `ColorSource` inputs and stitched color transforms. These serve different use cases but share the YCbCr-to-RGB concept.
- **MeshRenderPipeline:** MetalSprockets defines the base `MeshRenderPipeline` element; this package's `EdgeLinesRenderPipeline` and `GraphicsContext3DRenderPipeline` use it with their own mesh/object shaders. No duplication — just consumers of the base type.

Everything else in this package (mesh types, shape generators, lighting shaders, grid, axis lines, edge rendering, GraphicsContext3D, Slug text rendering) is unique to MetalSprocketsAddOns.
