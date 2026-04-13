# MetalSprocketsAddOns

Higher-level rendering pipelines, mesh utilities, and shaders built on top of [MetalSprockets](https://github.com/schwa/MetalSprockets).

## Targets

### MetalSprocketsAddOns

Ready-to-use MetalSprockets `Element` pipelines and mesh types.

**Render Pipelines:**

| Pipeline | Description |
|---|---|
| `FlatShader` | Unlit textured/colored mesh rendering with configurable `ColorSource` |
| `LambertianShader` | Simple diffuse lighting with a directional light |
| `GridShader` | Infinite ground-plane grid (XZ plane) |
| `WireframeRenderPipeline` | Triangle-fill-mode wireframe for `MTKMesh` |
| `EdgeLinesRenderPipeline` | Mesh-shader edge rendering with configurable line width (extracts unique edges) |
| `AxisLinesRenderPipeline` | Colored X/Y/Z axis lines with screen-space line width |
| `AxisAlignedWireframeBoxesRenderPipeline` | Instanced wireframe AABB boxes |
| `TextureBillboardPipeline` | Full-screen texture billboard with stitched color-transform functions |
| `TexturedQuad3DPipeline` | YCbCr-textured quad positioned in 3D world space |
| `GraphicsContext3DRenderPipeline` | Canvas-style 3D path stroking/filling with pixel-perfect line widths, caps, and joins |

**Mesh Types:**

| Type | Description |
|---|---|
| `TrivialMesh` | CPU-side mesh with positions, normals, tangents, UVs, colors, and indices |
| `Mesh` | GPU-backed mesh with `MTLBuffer` vertex/index buffers and a `VertexDescriptor` |
| `MeshWithEdges` | Mesh + extracted unique edge list for edge rendering |

`TrivialMesh` includes shape generators (box, sphere, cylinder, cone, torus, plane), tangent generation via MikkTSpace, and conversion to GPU `Mesh`.

**Other:**

- `GraphicsContext3D` / `Path3D` — SwiftUI `Canvas`-style API for recording stroke/fill commands on 3D paths (lines, quadratic/cubic curves, subpaths)
- `ColorSource` — enum wrapping texture2D, textureCube, depth2D, or solid color for shader parameterization
- `SimpleStitchedFunctionGraph` — helper for building Metal stitched function pipelines

### MetalSprocketsAddOnsShaders

Metal shaders (compiled via MetalCompilerPlugin) for all the pipelines above. Includes axis lines, boxes, edge rendering, flat/grid/lambertian/wireframe shaders, texture billboard, textured quad 3D, and GraphicsContext3D mesh/object shaders.

### MikkTSpace

Bundled C implementation of [MikkTSpace](http://www.mikktspace.com/) for tangent-space generation.

## Overlap with MetalSprockets

MetalSprockets core provides the rendering framework (Element tree, RenderPass, RenderPipeline, MeshRenderPipeline, Draw, etc.) but includes very few concrete shaders. Two areas of partial overlap:

- **YCbCr Billboard:** MetalSprockets has `YCbCrBillboardRenderPass` (in MetalSprocketsUI) for full-screen YCbCr camera/video backgrounds. This package has `TexturedQuad3DPipeline` which also renders YCbCr textures but on a 3D-positioned quad, and `TextureBillboardPipeline` which is a more general billboard with dual `ColorSource` inputs and stitched color transforms. These serve different use cases but share the YCbCr-to-RGB concept.
- **MeshRenderPipeline:** MetalSprockets defines the base `MeshRenderPipeline` element; this package's `EdgeLinesRenderPipeline` and `GraphicsContext3DRenderPipeline` use it with their own mesh/object shaders. No duplication — just consumers of the base type.

Everything else in this package (mesh types, shape generators, lighting shaders, grid, axis lines, edge rendering, GraphicsContext3D) is unique to MetalSprocketsAddOns.
