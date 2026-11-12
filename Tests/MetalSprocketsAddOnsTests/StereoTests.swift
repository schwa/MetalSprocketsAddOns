import CoreGraphics
import Metal
import MetalSprockets
@testable import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import MetalSupport
import simd
import SwiftMesh
import SwiftUI
import Testing

// Two views into a layered target: the left eye shifts geometry left, the right eye right.
@MainActor
private struct StereoTarget {
    static let size = 64
    let color: MTLTexture
    let renderer: OffscreenRenderer
    let views: StereoViews

    init() throws {
        let device = _MTLCreateSystemDefaultDevice()
        func arrayTexture(_ format: MTLPixelFormat) throws -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: Self.size, height: Self.size, mipmapped: false)
            descriptor.textureType = .type2DArray
            descriptor.arrayLength = 2
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = format == .depth32Float ? .private : .shared
            return try #require(device.makeTexture(descriptor: descriptor))
        }
        color = try arrayTexture(.rgba8Unorm)
        renderer = try OffscreenRenderer(size: CGSize(width: Self.size, height: Self.size), colorTexture: color, depthTexture: arrayTexture(.depth32Float))
        renderer.renderPassDescriptor.renderTargetArrayLength = 2
        let viewport = MTLViewport(originX: 0, originY: 0, width: Double(Self.size), height: Double(Self.size), znear: 0, zfar: 1)
        views = StereoViews(
            viewProjections: [float4x4(translation: [-0.5, 0, 0]), float4x4(translation: [0.5, 0, 0])],
            viewports: [viewport, viewport]
        )
    }

    // RGBA at a pixel (y down) of a slice.
    func pixel(x: Int, y: Int, slice: Int) -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        color.getBytes(&pixel, bytesPerRow: Self.size * 4, bytesPerImage: Self.size * Self.size * 4, from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0, slice: slice)
        return pixel
    }

    func red(x: Int, y: Int, slice: Int) -> UInt8 {
        pixel(x: x, y: y, slice: slice)[0]
    }

    // A centred shape lands at x = 16 in the left slice and x = 48 in the right.
    func expectShiftedPerEye(sourceLocation: SourceLocation = #_sourceLocation) {
        let middle = Self.size / 2
        #expect(red(x: 16, y: middle, slice: 0) > 128, "Left eye draws its view", sourceLocation: sourceLocation)
        #expect(red(x: 48, y: middle, slice: 0) == 0, "Left eye does not draw the right view", sourceLocation: sourceLocation)
        #expect(red(x: 48, y: middle, slice: 1) > 128, "Right eye draws its view", sourceLocation: sourceLocation)
        #expect(red(x: 16, y: middle, slice: 1) == 0, "Right eye does not draw the left view", sourceLocation: sourceLocation)
    }
}

@Test(.requiresMetal4)
@MainActor
func testStereo_silhouetteMask() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let positions: [SIMD3<Float>] = [[-0.2, -0.2, 0.5], [0.2, -0.2, 0.5], [0.2, 0.2, 0.5], [-0.2, 0.2, 0.5]]
    let topology = HalfEdgeTopology(vertexCount: 4, faces: [[0, 1, 2], [0, 2, 3]].map { HalfEdgeTopology.FaceDefinition(outer: $0) })
    let mesh = MetalMesh(mesh: Mesh(topology: topology, positions: positions), device: device)

    let target = try StereoTarget()
    _ = try target.renderer.render(try RenderPass {
        SilhouetteMaskRenderPipeline(instances: [.init(mesh: mesh)], views: target.views)
    })
    target.expectShiftedPerEye()
}

@MainActor
private let square = Path3D { path in
        path.move(to: [-0.2, -0.2, 0.5])
        path.addLine(to: [0.2, -0.2, 0.5])
        path.addLine(to: [0.2, 0.2, 0.5])
        path.addLine(to: [-0.2, 0.2, 0.5])
        path.closeSubpath()
}

@Test(.requiresMetal4)
@MainActor
func testStereo_graphicsContext3DFill() throws {
    let context = GraphicsContext3D { ctx in
        ctx.fill(square, with: .red)
    }
    let target = try StereoTarget()
    let viewport = SIMD2<Float>(Float(StereoTarget.size), Float(StereoTarget.size))
    _ = try target.renderer.render(try RenderPass {
        GraphicsContext3DRenderPipeline(context: context, views: target.views, viewport: viewport)
    })
    target.expectShiftedPerEye()
}

@Test(.requiresMetal4, .disabled(if: !supportsMeshShaders, "Stroking needs mesh shaders — see issue #29"))
@MainActor
func testStereo_graphicsContext3DStroke() throws {
    let context = GraphicsContext3D { ctx in
        ctx.stroke(
            Path3D { path in
                path.move(to: [-0.2, 0, 0.5])
                path.addLine(to: [0.2, 0, 0.5])
            },
            with: .red,
            lineWidth: 8
        )
    }
    let target = try StereoTarget()
    let viewport = SIMD2<Float>(Float(StereoTarget.size), Float(StereoTarget.size))
    _ = try target.renderer.render(try RenderPass {
        GraphicsContext3DRenderPipeline(context: context, views: target.views, viewport: viewport)
    })
    target.expectShiftedPerEye()
}

@Test(.requiresMetal4)
@MainActor
func testStereo_jumpFloodOutline() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let size = StereoTarget.size
    // One square per slice: x 8..<24 for the left eye, 40..<56 for the right.
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: size, height: size, mipmapped: false)
    descriptor.textureType = .type2DArray
    descriptor.arrayLength = 2
    descriptor.usage = [.shaderRead]
    descriptor.storageMode = .shared
    let mask = try #require(device.makeTexture(descriptor: descriptor))
    for (slice, columns) in [(0, 8..<24), (1, 40..<56)] {
        var pixels = [UInt8](repeating: 0, count: size * size)
        for y in 24..<40 {
            for x in columns {
                pixels[y * size + x] = 255
            }
        }
        mask.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0, slice: slice, withBytes: pixels, bytesPerRow: size, bytesPerImage: size * size)
    }
    let seeds = try JumpFloodPipeline.makeSeedTexture(device: device, width: size, height: size, arrayLength: 2)
    try JumpFloodPipeline(mask: mask, seeds: seeds, maximumDistance: 4).run()

    let target = try StereoTarget()
    _ = try target.renderer.render(try RenderPass {
        JumpFloodOutlineRenderPipeline(mask: mask, seeds: seeds, color: [1, 0, 0, 1], width: 4, views: target.views)
    })
    // Two pixels right of each eye's square is outline; the same spot in the other eye is not.
    #expect(target.red(x: 26, y: 32, slice: 0) > 128)
    #expect(target.red(x: 58, y: 32, slice: 0) == 0)
    #expect(target.red(x: 58, y: 32, slice: 1) > 128)
    #expect(target.red(x: 26, y: 32, slice: 1) == 0)
    #expect(target.red(x: 16, y: 32, slice: 0) == 0, "Inside of the mask is left unchanged")
}

@Test(.requiresMetal4)
@MainActor
func testStereo_debugRenderPipeline() throws {
    let mesh = try makeBoxMeshWithTangents(extent: [0.4, 0.4, 0.4])
    let target = try StereoTarget()
    let views = target.views
    _ = try target.renderer.render(try RenderPass {
        try DebugRenderPipeline(
            modelMatrix: float4x4(translation: [0, 0, 0.5]),
            normalMatrix: matrix_identity_float3x3,
            debugMode: .amplificationID,
            lightPosition: [0, 0, -1],
            cameraPosition: [0, 0, -1],
            views: views
        ) {
            Draw { encoder in
                views.configure(encoder)
                encoder.draw(mesh)
            }
            .vertexBuffers(of: mesh)
            .useResources(mesh.submeshes.map(\.indexBuffer.buffer), usage: .read, stages: .vertex)
        }
        .vertexDescriptor(mesh.vertexDescriptor)
    })
    // Amplification ID 0 is drawn red, 1 green; each at its own view's position.
    let left = target.pixel(x: 16, y: 32, slice: 0)
    let right = target.pixel(x: 48, y: 32, slice: 1)
    #expect(left[0] > 200 && left[1] < 100, "Left eye draws its view as amplification 0: \(left)")
    #expect(right[1] > 200 && right[0] < 100, "Right eye draws its view as amplification 1: \(right)")
    #expect(target.pixel(x: 48, y: 32, slice: 0) == [0, 0, 0, 255])
    #expect(target.pixel(x: 16, y: 32, slice: 1) == [0, 0, 0, 255])
}

@Test(.requiresMetal4)
@MainActor
func testStereo_blinnPhong() throws {
    let mesh = try makeBoxMeshWithTangents(extent: [0.4, 0.4, 0.4])
    // Only ambient light reaches the camera, so the box is flat red.
    let lighting = try Lighting(ambientLightColor: [1, 1, 1], lights: [([0, 0, 10], Light(type: .point, color: [0, 0, 0], intensity: 0))])
    let material = BlinnPhongMaterial(ambient: .color([1, 0, 0]), diffuse: .color([0, 0, 0]), specular: .color([0, 0, 0]), shininess: 1)
    let target = try StereoTarget()
    let views = target.views
    _ = try target.renderer.render(try RenderPass {
        try BlinnPhongShader(viewCount: views.count) {
            try Draw { encoder in
                views.configure(encoder)
                encoder.draw(mesh)
            }
            .vertexBuffers(of: mesh)
            .useResources(mesh.submeshes.map(\.indexBuffer.buffer), usage: .read, stages: .vertex)
            .blinnPhongMaterial(material)
            .blinnPhongMatrices(modelMatrix: float4x4(translation: [0, 0, 0.5]), cameraMatrix: float4x4(translation: [0, 0, -1]), views: views)
            .lighting(lighting)
        }
        .vertexDescriptor(mesh.vertexDescriptor)
    })
    target.expectShiftedPerEye()
}

#if arch(arm64)
@Test(.requiresMetal4)
@MainActor
func testStereo_graphicsContext3DText() throws {
    let context = GraphicsContext3D { ctx in
        ctx.text("\u{2588}", at: [0, 0, 0.5], with: .red, fontSize: 12)
    }
    let target = try StereoTarget()
    let viewport = SIMD2<Float>(Float(StereoTarget.size), Float(StereoTarget.size))
    _ = try target.renderer.render(try RenderPass {
        GraphicsContext3DRenderPipeline(context: context, views: target.views, viewport: viewport)
    })
    // The brightest red within a few pixels of each eye's label position.
    func maximumRed(aroundX centerX: Int, slice: Int) -> UInt8 {
        var result: UInt8 = 0
        for y in 28 ... 36 {
            for x in centerX - 4 ... centerX + 4 {
                result = max(result, target.red(x: x, y: y, slice: slice))
            }
        }
        return result
    }
    #expect(maximumRed(aroundX: 16, slice: 0) > 128, "Left eye draws the label at its view's position")
    #expect(maximumRed(aroundX: 48, slice: 0) == 0)
    #expect(maximumRed(aroundX: 48, slice: 1) > 128, "Right eye draws the label at its view's position")
    #expect(maximumRed(aroundX: 16, slice: 1) == 0)
}
#endif
