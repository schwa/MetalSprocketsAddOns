import CoreGraphics
import GeometryLite3D
import Metal
import MetalKit
import MetalSprockets
@testable import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import MetalSupport
import simd
import Testing

private let size = SIMD2<Int>(Int(defaultRenderSize.width), Int(defaultRenderSize.height))

private func viewProjection() -> float4x4 {
    perspectiveProjection() * float4x4(translation: SIMD3<Float>(0, 0, 3)).inverse
}

private func makePointBuffer(_ points: [PointCloudPoint]) throws -> MTLBuffer {
    try _MTLCreateSystemDefaultDevice().makeBuffer(unsafeBytesOf: points)
}

/// Renders `points` (and optionally an occluding quad) and returns BGRA8 pixels, top row first.
@MainActor
private func render(_ points: [PointCloudPoint], occluder: Bool = false) throws -> [SIMD4<UInt8>] {
    let buffer = try makePointBuffer(points)
    let framebuffer = PointCloudFramebuffer()
    let viewProjection = viewProjection()
    let quad = MTKMesh.plane(width: 1, height: 2)
    let element = try MetalSprockets.Group {
        try PointCloudRasterizePass(points: buffer, count: points.count, viewProjection: viewProjection, viewportSize: size, framebuffer: framebuffer)
        try RenderPass {
            if occluder {
                // Covers the left half of the view at z = 0.5.
                try FlatShader(
                    modelViewProjection: viewProjection * float4x4(translation: SIMD3<Float>(-0.5, 0, 0.5)),
                    textureSpecifier: ColorSource.color([0, 0, 1])
                ) {
                    Draw(mesh: quad)
                    .vertexBuffers(of: quad)
                }
                .vertexDescriptor(MTLVertexDescriptor(quad.vertexDescriptor))
                .depthCompare(function: .less, enabled: true)
            }
            try PointCloudResolvePipeline(framebuffer: framebuffer)
        }
    }
    let rendering = try OffscreenRenderer(size: defaultRenderSize).render(element)
    var pixels = [SIMD4<UInt8>](repeating: .zero, count: size.x * size.y)
    rendering.texture.getBytes(&pixels, bytesPerRow: size.x * 4, from: MTLRegionMake2D(0, 0, size.x, size.y), mipmapLevel: 0)
    return pixels
}

private func pixel(of world: SIMD3<Float>) -> Int {
    let clip = viewProjection() * SIMD4<Float>(world, 1)
    let ndc = SIMD2<Float>(clip.x, clip.y) / clip.w
    let x = Int((ndc.x * 0.5 + 0.5) * Float(size.x))
    let y = Int((0.5 - ndc.y * 0.5) * Float(size.y))
    return y * size.x + x
}

@Test(.requiresMetal4)
@MainActor
func testPointCloud_nearestPointWinsPerPixel() throws {
    // Two points on the same view ray: the red one is nearer the camera.
    let far = SIMD3<Float>(0.2, 0.1, -1)
    let near = far * 0.5 + SIMD3<Float>(0, 0, 3) * 0.5
    let pixels = try render([
        PointCloudPoint(position: far, color: [0, 255, 0, 255]),
        PointCloudPoint(position: near, color: [255, 0, 0, 255])
    ])
    let bgra = pixels[pixel(of: far)]
    #expect(bgra.z > 200 && bgra.y < 50)
}

@Test(.requiresMetal4)
@MainActor
func testPointCloud_depthTestsAgainstOtherGeometry() throws {
    // Both points sit behind the quad's z, one on each side; only the right one stays visible.
    let hidden = SIMD3<Float>(-0.5, 0, 0)
    let visible = SIMD3<Float>(0.5, 0, 0)
    let pixels = try render([
        PointCloudPoint(position: hidden, color: [255, 0, 0, 255]),
        PointCloudPoint(position: visible, color: [255, 0, 0, 255])
    ], occluder: true)
    #expect(pixels[pixel(of: hidden)].z < 50)
    #expect(pixels[pixel(of: visible)].z > 200)
}

@Test(.requiresMetal4)
@MainActor
func testPointCloud_goldenImage() throws {
    // A dense, deterministic helix of points coloured by height.
    let count = 20_000
    let points = (0..<count).map { index in
        let t = Float(index) / Float(count)
        let angle = t * .pi * 12
        let position = SIMD3<Float>(cos(angle) * 0.8, t * 2 - 1, sin(angle) * 0.8)
        let color = SIMD4<UInt8>(UInt8(t * 255), UInt8((1 - t) * 255), 200, 255)
        return PointCloudPoint(position: position, color: color)
    }
    let buffer = try makePointBuffer(points)
    let framebuffer = PointCloudFramebuffer()
    let element = try MetalSprockets.Group {
        try PointCloudRasterizePass(points: buffer, count: count, viewProjection: viewProjection(), viewportSize: size, framebuffer: framebuffer)
        try RenderPass {
            try PointCloudResolvePipeline(framebuffer: framebuffer)
        }
    }
    let image = try OffscreenRenderer(size: defaultRenderSize).render(element).cgImage
    #expect(try image.isEqualToGoldenImage(named: "PointCloudHelix"))
}

@Test
func testPointCloudPoint_packsColorRedInLowestByte() {
    let point = PointCloudPoint(position: .zero, color: [0x11, 0x22, 0x33, 0x44])
    #expect(point.color == 0x4433_2211)
}
