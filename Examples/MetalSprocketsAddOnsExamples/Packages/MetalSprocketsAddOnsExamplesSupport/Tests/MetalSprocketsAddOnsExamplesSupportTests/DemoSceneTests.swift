import CoreGraphics
import Metal
import MetalSprockets
import MetalSprocketsAddOns
@testable import MetalSprocketsAddOnsExamplesSupport
import simd
import Testing

// Renders each demo's scene offscreen with a fixed camera and time, so broken demos fail here
// instead of only in the running app (#59).

@Test(.requiresMetal4)
@MainActor
func testShadowMapDemoScene() throws {
    let scene = ShadowMapDemoScene()
    let camera = OrbitCamera(pitch: -.pi / 7, distance: 9, target: [0, 0.5, 0])
    // The shadow mask reads scene depth and writes colour from a compute pass.
    let renderer = try OffscreenRenderer(
        size: demoRenderSize,
        colorUsage: [.renderTarget, .shaderRead, .shaderWrite],
        depthUsage: [.renderTarget, .shaderRead]
    )
    renderer.renderPassDescriptor.colorAttachments[0].clearColor = ShadowMapDemoScene.clearColor
    let element = scene.element(
        shadowMap: try ShadowMap(resolution: 1_024, lightCount: 1),
        lightPosition: ShadowMapDemoScene.lightPosition(at: 1),
        viewProjection: camera.projectionMatrix(drawableSize: demoRenderSize) * camera.viewMatrix,
        shadowIntensity: 0.8,
        depthBias: 2,
        slopeScale: 4,
        showShadows: true
    )
    let image = try renderer.render(element).cgImage
    #expect(try image.isEqualToGoldenImage(named: "ShadowMapDemo"))
}

@Test(.requiresMetal4)
@MainActor
func testBlinnPhongDemoScene() throws {
    let scene = BlinnPhongDemoScene()
    let lighting = try BlinnPhongDemoScene.makeLighting()
    for (index, position) in BlinnPhongDemoScene.lightPositions(at: 1).enumerated() {
        lighting.setLightPosition(position, at: index)
    }
    let camera = OrbitCamera(pitch: -.pi / 8, distance: 6, target: [0, 0.2, 0])
    let renderer = try OffscreenRenderer(size: demoRenderSize)
    renderer.renderPassDescriptor.colorAttachments[0].clearColor = BlinnPhongDemoScene.clearColor
    let element = try scene.element(
        lighting: lighting,
        camera: camera,
        projection: camera.projectionMatrix(drawableSize: demoRenderSize),
        shininess: 64,
        showGrid: true
    )
    let image = try renderer.render(element).cgImage
    #expect(try image.isEqualToGoldenImage(named: "BlinnPhongDemo"))
}

@Test(.requiresMetal4)
@MainActor
func testDebugShadingDemoScene() throws {
    let scene = DebugShadingDemoScene()
    let camera = OrbitCamera(pitch: -.pi / 8, distance: 4)
    let renderer = try OffscreenRenderer(size: demoRenderSize)
    renderer.renderPassDescriptor.colorAttachments[0].clearColor = DebugShadingDemoScene.clearColor
    let element = try scene.element(
        useSphere: true,
        debugMode: .normal,
        wireframe: false,
        camera: camera,
        projection: camera.projectionMatrix(drawableSize: demoRenderSize)
    )
    let image = try renderer.render(element).cgImage
    #expect(try image.isEqualToGoldenImage(named: "DebugShadingDemo"))
}

@Test(.requiresMetal4)
@MainActor
func testGraphicsContext3DDemoScene() throws {
    let camera = OrbitCamera(pitch: -.pi / 6, distance: 5)
    let renderer = try OffscreenRenderer(size: demoRenderSize)
    renderer.renderPassDescriptor.colorAttachments[0].clearColor = GraphicsContext3DDemoScene.clearColor
    let element = try RenderPass {
        GraphicsContext3DRenderPipeline(
            context: GraphicsContext3DDemoScene.context(lineWidth: 6, lineCap: .round, lineJoin: .round, showFill: true),
            viewProjection: camera.projectionMatrix(drawableSize: demoRenderSize) * camera.viewMatrix,
            viewport: SIMD2<Float>(Float(demoRenderSize.width), Float(demoRenderSize.height))
        )
    }
    let image = try renderer.render(element).cgImage
    #expect(try image.isEqualToGoldenImage(named: "GraphicsContext3DDemo"))
}

@Test(.requiresMetal4)
@MainActor
func testSlugTextDemoScene() throws {
    let scene = try SlugTextDemoScene.makeScene(text: "Metal\nSprockets", fontSize: 144)
    let mesh = try #require(scene.meshes.first)
    SlugTextDemoScene.setSpin(1, in: scene)
    let camera = SlugTextDemoScene.framingCamera(for: mesh, pitch: -.pi / 12)
    let renderer = try OffscreenRenderer(size: demoRenderSize)
    renderer.renderPassDescriptor.colorAttachments[0].clearColor = SlugTextDemoScene.clearColor
    let element = try SlugTextDemoScene.element(scene: scene, camera: camera, drawableSize: demoRenderSize, wireframe: false)
    let image = try renderer.render(element).cgImage
    #expect(try image.isEqualToGoldenImage(named: "SlugTextDemo"))
}

@Test(.requiresMetal4, .disabled(if: !supportsRaytracing, "Ray tracing unsupported on this GPU"))
@MainActor
func testRayTracedShadowsDemoScene() throws {
    let scene = try RayTracedShadowsDemoScene()
    scene.lighting.setLightPosition(RayTracedShadowsDemoScene.lightPosition(at: 1), at: 0)
    let camera = OrbitCamera(pitch: -.pi / 7, distance: 9, target: [0, 0.5, 0])
    // The shadow pass reads scene depth and writes colour from a compute pass.
    let renderer = try OffscreenRenderer(
        size: demoRenderSize,
        colorUsage: [.renderTarget, .shaderRead, .shaderWrite],
        depthUsage: [.renderTarget, .shaderRead]
    )
    renderer.renderPassDescriptor.colorAttachments[0].clearColor = RayTracedShadowsDemoScene.clearColor
    let element = RayTracedShadowsElement(
        scene: scene,
        viewProjection: camera.projectionMatrix(drawableSize: demoRenderSize) * camera.viewMatrix,
        shadowIntensity: 0.85,
        showShadows: true,
        debug: false
    )
    let image = try renderer.render(element).cgImage
    #expect(try image.isEqualToGoldenImage(named: "RayTracedShadowsDemo"))
}

@Test(.requiresMetal4, .disabled(if: !supportsPointCloud, "64-bit atomics unsupported on this GPU"))
@MainActor
func testPointCloudDemoScene() throws {
    let scene = try PointCloudDemoScene(pointCount: 100_000, colorMode: .position)
    let camera = OrbitCamera(pitch: -.pi / 8, distance: 6, target: [0, 0.5, 0])
    let renderer = try OffscreenRenderer(size: demoRenderSize)
    renderer.renderPassDescriptor.colorAttachments[0].clearColor = PointCloudDemoScene.clearColor
    let element = try scene.element(camera: camera, drawableSize: demoRenderSize, showGrid: true)
    let image = try renderer.render(element).cgImage
    #expect(try image.isEqualToGoldenImage(named: "PointCloudDemo"))
}
