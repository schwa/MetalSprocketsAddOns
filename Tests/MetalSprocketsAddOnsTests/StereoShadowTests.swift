// Layered (one view per array slice) shadow masking and compositing (#120).

import CoreGraphics
import Metal
import MetalSprockets
@testable import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import MetalSupport
import simd
import Testing

@MainActor
private func makeTexture(_ format: MTLPixelFormat, size: Int, arrayLength: Int? = nil, usage: MTLTextureUsage) throws -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: size, height: size, mipmapped: false)
    if let arrayLength {
        descriptor.textureType = .type2DArray
        descriptor.arrayLength = arrayLength
    }
    descriptor.usage = usage
    descriptor.storageMode = format == .depth32Float ? .private : .shared
    return try #require(_MTLCreateSystemDefaultDevice().makeTexture(descriptor: descriptor))
}

@MainActor
private func readPixels(_ texture: MTLTexture, slice: Int) -> [UInt8] {
    let size = texture.width
    var pixels = [UInt8](repeating: 0, count: size * size * 4)
    texture.getBytes(&pixels, bytesPerRow: size * 4, bytesPerImage: size * size * 4, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0, slice: slice)
    return pixels
}

@MainActor
private func stereoShadowViews(scene: ShadowTestScene) -> StereoViews {
    let size = Double(defaultRenderSize.width)
    let viewport = MTLViewport(originX: 0, originY: 0, width: size, height: size, znear: 0, zfar: 1)
    let camera = scene.viewTransforms.cameraMatrix
    let cameras = [camera * float4x4(translation: [-0.3, 0, 0]), camera * float4x4(translation: [0.3, 0, 0])]
    return StereoViews(viewMatrices: cameras.map(\.inverse), projectionMatrices: [perspectiveProjection(), perspectiveProjection()], viewports: [viewport, viewport])
}

@MainActor
private func makeShadowMap(scene: ShadowTestScene) throws -> ShadowMap {
    var shadowMap = try ShadowMap(resolution: 512)
    shadowMap.updateDirectionalLight(at: 0, position: scene.lightPosition, orthoSize: 3, near: 0.1, far: 20)
    return shadowMap
}

@MainActor
private func shadowCasters(scene: ShadowTestScene) throws -> some Element {
    try MetalSprockets.Group {
        Draw(mesh: scene.sphere)
            .vertexBuffers(of: scene.sphere)
            .parameter("modelMatrix", functionType: .vertex, value: scene.sphereTransform)
        Draw(mesh: scene.plane)
            .vertexBuffers(of: scene.plane)
            .parameter("modelMatrix", functionType: .vertex, value: scene.planeTransform)
    }
}

/// Renders the test scene for two views through `technique`: each view alone with a 2D context, then both at once
/// with a layered context, and checks every slice matches its view rendered alone.
@MainActor
private func expectLayeredMatchesEachViewAlone(scene: ShadowTestScene, technique: some ShadowTechnique) throws {
    let views = stereoShadowViews(scene: scene)
    let size = Int(defaultRenderSize.width)

    // Reference: each view on its own, through the plain 2D shadow chain.
    let references = try views.viewProjections.indices.map { index in
        let viewProjection = views.viewProjections[index]
        let color = try makeTexture(.rgba8Unorm, size: size, usage: ShadowContext.requiredColorUsage)
        let depth = try makeTexture(.depth32Float, size: size, usage: ShadowContext.requiredDepthUsage)
        let renderer = try OffscreenRenderer(size: defaultRenderSize, colorTexture: color, depthTexture: depth)
        let viewTransforms = ViewTransforms(projectionMatrix: views.projectionMatrices[index], cameraMatrix: views.cameraMatrices[index])
        let context = try ShadowContext(viewTransforms: viewTransforms, colorTexture: color, depthTexture: depth)
        _ = try renderer.render(try ShadowedScene(technique: technique, context: context) {
            try scene.scenePass(viewProjection: viewProjection)
        })
        return readPixels(color, slice: 0)
    }

    // Layered: each view drawn into its own slice, then one layered shadow pass for both.
    let color = try makeTexture(.rgba8Unorm, size: size, arrayLength: 2, usage: ShadowContext.requiredColorUsage)
    let depth = try makeTexture(.depth32Float, size: size, arrayLength: 2, usage: ShadowContext.requiredDepthUsage)
    let renderer = try OffscreenRenderer(size: defaultRenderSize, colorTexture: color, depthTexture: depth)
    for (slice, viewProjection) in views.viewProjections.enumerated() {
        renderer.renderPassDescriptor.colorAttachments[0].slice = slice
        renderer.renderPassDescriptor.depthAttachment.slice = slice
        _ = try renderer.render(try scene.scenePass(viewProjection: viewProjection))
    }
    let context = try ShadowContext(views: views, colorTexture: color, depthTexture: depth)
    _ = try renderer.render(try MetalSprockets.Group {
        try technique.passesBeforeScene(context: context)
        try technique.passesAfterScene(context: context)
    })

    for slice in 0..<2 {
        let layered = readPixels(color, slice: slice)
        let differing = zip(layered, references[slice]).filter { abs(Int($0) - Int($1)) > 2 }.count
        // The 2D path inverts the view-projection differently, so a few pixels on shadow edges may round the other way.
        #expect(differing < 64, "Slice \(slice): \(differing) bytes differ from the view rendered alone")
    }
    // The two views see the scene from different places, so the test would catch swapped slices.
    #expect(references[0] != references[1])
}

@Test(.requiresMetal4)
@MainActor
func testStereoShadows_layeredShadowMapMatchesEachViewAlone() throws {
    let scene = try ShadowTestScene()
    let technique = try ShadowMapTechnique(shadowMap: makeShadowMap(scene: scene), vertexDescriptor: scene.sphere.vertexDescriptor) { try shadowCasters(scene: scene) }
    try expectLayeredMatchesEachViewAlone(scene: scene, technique: technique)
}

@Test(.requiresMetal4, .disabled(if: !supportsRaytracing, "Ray tracing unsupported on this GPU — see issue #29"))
@MainActor
func testStereoShadows_layeredRayTracedMatchesEachViewAlone() throws {
    let scene = try ShadowTestScene()
    let lighting = try Lighting(ambientLightColor: [0, 0, 0], lights: [(scene.lightPosition, Light(type: .point, color: [1, 1, 1], intensity: 30))])
    let technique = try RayTracedShadowTechnique(
        meshes: [scene.sphere, scene.plane],
        instances: [
            AccelerationStructureManager.Instance(meshIndex: 0, transform: scene.sphereTransform),
            AccelerationStructureManager.Instance(meshIndex: 1, transform: scene.planeTransform)
        ],
        lighting: lighting
    )
    try expectLayeredMatchesEachViewAlone(scene: scene, technique: technique)
}

@Test(.requiresMetal4)
@MainActor
func testStereoShadows_layeredContextRejects2DTextures() throws {
    let scene = try ShadowTestScene()
    let color = try makeTexture(.rgba8Unorm, size: 8, usage: ShadowContext.requiredColorUsage)
    let depth = try makeTexture(.depth32Float, size: 8, usage: ShadowContext.requiredDepthUsage)
    #expect(throws: (any Error).self) {
        try ShadowContext(views: stereoShadowViews(scene: scene), colorTexture: color, depthTexture: depth)
    }
}

/// Clears each slice of a colour and depth array to its own values.
@MainActor
private func clearSlices(color: MTLTexture, depth: MTLTexture, colors: [MTLClearColor], depths: [Double]) throws {
    let renderer = try OffscreenRenderer(size: CGSize(width: color.width, height: color.height), colorTexture: color, depthTexture: depth)
    for slice in colors.indices {
        renderer.renderPassDescriptor.colorAttachments[0].slice = slice
        renderer.renderPassDescriptor.colorAttachments[0].clearColor = colors[slice]
        renderer.renderPassDescriptor.depthAttachment.slice = slice
        renderer.renderPassDescriptor.depthAttachment.clearDepth = depths[slice]
        _ = try renderer.render(try RenderPass { EmptyElement() })
    }
}

@Test(.requiresMetal4)
@MainActor
func testStereoShadows_compositeLayeredTarget() throws {
    let size = 64
    let color = try makeTexture(.rgba8Unorm, size: size, arrayLength: 2, usage: [.renderTarget, .shaderRead])
    let depth = try makeTexture(.depth32Float, size: size, arrayLength: 2, usage: [.renderTarget, .shaderRead])
    // View 0 is red at depth 0.5; view 1 was never drawn (still at the clear depth, 1).
    try clearSlices(color: color, depth: depth, colors: [MTLClearColor(red: 1, green: 0, blue: 0, alpha: 1), MTLClearColor(red: 0, green: 1, blue: 0, alpha: 1)], depths: [0.5, 1])

    let target = try makeTexture(.rgba8Unorm, size: size, arrayLength: 2, usage: [.renderTarget, .shaderRead])
    let targetDepth = try makeTexture(.depth32Float, size: size, arrayLength: 2, usage: [.renderTarget])
    let renderer = try OffscreenRenderer(size: CGSize(width: size, height: size), colorTexture: target, depthTexture: targetDepth)
    renderer.renderPassDescriptor.renderTargetArrayLength = 2
    let viewport = MTLViewport(originX: 0, originY: 0, width: Double(size), height: Double(size), znear: 0, zfar: 1)
    let views = StereoViews(viewMatrices: [matrix_identity_float4x4, matrix_identity_float4x4], projectionMatrices: [matrix_identity_float4x4, matrix_identity_float4x4], viewports: [viewport, viewport])
    _ = try renderer.render(try RenderPass {
        try LayeredCompositeRenderPipeline(color: color, depth: depth, views: views, clearDepth: 1, depthCompareFunction: .less)
    })
    let left = readPixels(target, slice: 0)
    let right = readPixels(target, slice: 1)
    #expect(Array(left[0..<4]) == [255, 0, 0, 255], "View 0's slice is copied")
    #expect(Array(right[0..<4]) == [0, 0, 0, 255], "View 1's undrawn pixels leave the target alone")
}

@Test(.requiresMetal4)
@MainActor
func testStereoShadows_compositeSideBySide() throws {
    let size = 32
    let color = try makeTexture(.rgba8Unorm, size: size, arrayLength: 2, usage: [.renderTarget, .shaderRead])
    let depth = try makeTexture(.depth32Float, size: size, arrayLength: 2, usage: [.renderTarget, .shaderRead])
    try clearSlices(color: color, depth: depth, colors: [MTLClearColor(red: 1, green: 0, blue: 0, alpha: 1), MTLClearColor(red: 0, green: 1, blue: 0, alpha: 1)], depths: [0.5, 0.5])

    let renderer = try OffscreenRenderer(size: CGSize(width: size * 2, height: size))
    let views = StereoViews(
        viewMatrices: [matrix_identity_float4x4, matrix_identity_float4x4],
        projectionMatrices: [matrix_identity_float4x4, matrix_identity_float4x4],
        viewports: [
            MTLViewport(originX: 0, originY: 0, width: Double(size), height: Double(size), znear: 0, zfar: 1),
            MTLViewport(originX: Double(size), originY: 0, width: Double(size), height: Double(size), znear: 0, zfar: 1)
        ]
    )
    let rendering = try renderer.render(try RenderPass {
        try LayeredCompositeRenderPipeline(color: color, depth: depth, views: views, clearDepth: 1, depthCompareFunction: .less)
    })
    let image = try rendering.cgImage
    #expect(try image.pixel(atX: 5, y: 5) == [255, 0, 0, 255], "Left half shows view 0")
    #expect(try image.pixel(atX: size + 5, y: 5) == [0, 255, 0, 255], "Right half shows view 1")
}
