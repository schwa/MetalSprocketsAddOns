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

private func viewProjection(reverseZ: Bool = false) -> float4x4 {
    let projection = reverseZ
        ? PerspectiveProjection(verticalAngleOfView: .degrees(60), depthMode: .reversed(zMin: 0.1)).projectionMatrix(aspectRatio: 1)
        : perspectiveProjection()
    return projection * float4x4(translation: SIMD3<Float>(0, 0, 3)).inverse
}

private func makePointBuffer(_ points: [PointCloudPoint]) throws -> MTLBuffer {
    try _MTLCreateSystemDefaultDevice().makeBuffer(unsafeBytesOf: points)
}

/// Renders `points` (and optionally an occluding quad) and returns BGRA8 pixels, top row first.
@MainActor
private func render(
    _ points: [PointCloudPoint],
    occluder: Bool = false,
    reverseZ: Bool = false,
    pointSize: Float = 1,
    shape: PointCloudShape = .square,
    maximumPointSize: Float = 64
) throws -> [SIMD4<UInt8>] {
    try render(buffer: makePointBuffer(points), count: points.count, occluder: occluder, reverseZ: reverseZ, pointSize: pointSize, shape: shape, maximumPointSize: maximumPointSize)
}

@MainActor
private func render(
    buffer: MTLBuffer,
    count: Int,
    occluder: Bool = false,
    reverseZ: Bool = false,
    pointSize: Float = 1,
    shape: PointCloudShape = .square,
    maximumPointSize: Float = 64,
    colorSpace: PointCloudColorSpace = .sRGB,
    describe: PointCloudPointFunction? = nil
) throws -> [SIMD4<UInt8>] {
    let framebuffer = PointCloudFramebuffer()
    let viewProjection = viewProjection(reverseZ: reverseZ)
    let quad = MTKMesh.plane(width: 1, height: 2)
    let element = try MetalSprockets.Group {
        try PointCloudRasterizePass(
            points: buffer,
            count: count,
            viewProjection: viewProjection,
            viewportSize: size,
            reverseZ: reverseZ,
            framebuffer: framebuffer,
            pointSize: pointSize,
            shape: shape,
            maximumPointSize: maximumPointSize,
            colorSpace: colorSpace,
            describe: describe
        )
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
                .depthCompare(function: reverseZ ? .greater : .less, enabled: true)
            }
            try PointCloudResolvePipeline(framebuffer: framebuffer)
        }
    }
    let rendering = try OffscreenRenderer(size: defaultRenderSize, clearDepth: reverseZ ? 0 : 1).render(element)
    var pixels = [SIMD4<UInt8>](repeating: .zero, count: size.x * size.y)
    rendering.texture.getBytes(&pixels, bytesPerRow: size.x * 4, from: MTLRegionMake2D(0, 0, size.x, size.y), mipmapLevel: 0)
    return pixels
}

/// The pixel a world-space point projects to, origin top-left.
private func pixelCoordinate(of world: SIMD3<Float>) -> SIMD2<Int> {
    let clip = viewProjection() * SIMD4<Float>(world, 1)
    let ndc = SIMD2<Float>(clip.x, clip.y) / clip.w
    return SIMD2<Int>(Int((ndc.x * 0.5 + 0.5) * Float(size.x)), Int((0.5 - ndc.y * 0.5) * Float(size.y)))
}

private func pixel(of world: SIMD3<Float>) -> Int {
    let coordinate = pixelCoordinate(of: world)
    return coordinate.y * size.x + coordinate.x
}

/// Whether the pixel `offset` from `world`'s pixel is lit (non-black).
private func isLit(_ pixels: [SIMD4<UInt8>], at world: SIMD3<Float>, offset: SIMD2<Int>) -> Bool {
    let coordinate = pixelCoordinate(of: world) &+ offset
    let pixel = pixels[coordinate.y * size.x + coordinate.x]
    return max(pixel.x, pixel.y, pixel.z) > 100
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

// Issue #82: the same two checks with a reverse-Z projection and depth buffer (cleared to 0, compare .greater).
@Test(.requiresMetal4)
@MainActor
func testPointCloud_reverseZ_nearestPointWinsPerPixel() throws {
    let far = SIMD3<Float>(0.2, 0.1, -1)
    let near = far * 0.5 + SIMD3<Float>(0, 0, 3) * 0.5
    let pixels = try render([
        PointCloudPoint(position: far, color: [0, 255, 0, 255]),
        PointCloudPoint(position: near, color: [255, 0, 0, 255])
    ], reverseZ: true)
    let bgra = pixels[pixel(of: far)]
    #expect(bgra.z > 200 && bgra.y < 50)
}

@Test(.requiresMetal4)
@MainActor
func testPointCloud_reverseZ_depthTestsAgainstOtherGeometry() throws {
    let hidden = SIMD3<Float>(-0.5, 0, 0)
    let visible = SIMD3<Float>(0.5, 0, 0)
    let points = [
        PointCloudPoint(position: hidden, color: [255, 0, 0, 255]),
        PointCloudPoint(position: visible, color: [255, 0, 0, 255])
    ]
    let pixels = try render(points, occluder: true, reverseZ: true)
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

// MARK: - Frames in flight

// Issue #89: each submission rasterizes into its own buffer, one per frame in flight, so a frame
// never clears a buffer an earlier frame may still be resolving.
@Test(.requiresMetal4)
@MainActor
func testPointCloud_framebufferHasOneBufferPerFrameInFlight() throws {
    let buffer = try makePointBuffer([PointCloudPoint(position: .zero, color: [255, 255, 255, 255])])
    let framebuffer = PointCloudFramebuffer()
    // OffscreenRenderer's runner allows 3 submissions in flight.
    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    var used: [ObjectIdentifier] = []
    for _ in 0..<4 {
        let element = try MetalSprockets.Group {
            try PointCloudRasterizePass(points: buffer, count: 1, viewProjection: viewProjection(), viewportSize: size, framebuffer: framebuffer)
            try RenderPass {
                try PointCloudResolvePipeline(framebuffer: framebuffer)
            }
        }
        _ = try renderer.render(element)
        used.append(ObjectIdentifier(try #require(framebuffer.buffer)))
    }
    #expect(Set(used.prefix(3)).count == 3)
    #expect(used[3] == used[0])
}

// MARK: - Colour space

// Issue #81: OffscreenRenderer targets bgra8Unorm_srgb. sRGB-encoded colours must round-trip;
// linear colours get sRGB-encoded on write.
@Test(.requiresMetal4)
@MainActor
func testPointCloud_srgbColoursRoundTripOnSrgbTarget() throws {
    let position = SIMD3<Float>(0.2, 0.1, 0)
    let buffer = try makePointBuffer([PointCloudPoint(position: position, color: [128, 128, 128, 255])])
    let srgb = try render(buffer: buffer, count: 1, colorSpace: .sRGB)[pixel(of: position)]
    let linear = try render(buffer: buffer, count: 1, colorSpace: .linear)[pixel(of: position)]
    #expect(abs(Int(srgb.y) - 128) <= 1)
    #expect(abs(Int(linear.y) - 188) <= 2)
}

// MARK: - Sizes and shapes

private let centre = SIMD3<Float>(0.1, 0.05, 0)
private let white = SIMD4<UInt8>(255, 255, 255, 255)

@Test(.requiresMetal4)
@MainActor
func testPointCloud_squareFillsItsBox() throws {
    let pixels = try render([PointCloudPoint(position: centre, color: white)], pointSize: 9, shape: .square)
    #expect(isLit(pixels, at: centre, offset: [3, 3]))
    #expect(isLit(pixels, at: centre, offset: [-3, -3]))
    #expect(!isLit(pixels, at: centre, offset: [7, 0]))
}

@Test(.requiresMetal4)
@MainActor
func testPointCloud_discLeavesCornersEmpty() throws {
    let pixels = try render([PointCloudPoint(position: centre, color: white)], pointSize: 21, shape: .disc)
    #expect(isLit(pixels, at: centre, offset: [8, 0]))
    #expect(isLit(pixels, at: centre, offset: [0, -8]))
    #expect(!isLit(pixels, at: centre, offset: [8, 8]))
}

@Test(.requiresMetal4)
@MainActor
func testPointCloud_crosshairIsTwoLines() throws {
    let pixels = try render([PointCloudPoint(position: centre, color: white)], pointSize: 15, shape: .crosshair)
    #expect(isLit(pixels, at: centre, offset: [6, 0]) || isLit(pixels, at: centre, offset: [6, 1]))
    #expect(isLit(pixels, at: centre, offset: [0, -6]) || isLit(pixels, at: centre, offset: [1, -6]))
    #expect(!isLit(pixels, at: centre, offset: [4, 4]))
}

@Test(.requiresMetal4)
@MainActor
func testPointCloud_ringIsHollow() throws {
    let pixels = try render([PointCloudPoint(position: centre, color: white)], pointSize: 25, shape: .ring)
    #expect(isLit(pixels, at: centre, offset: [11, 0]))
    #expect(!isLit(pixels, at: centre, offset: [0, 0]))
    #expect(!isLit(pixels, at: centre, offset: [4, 0]))
}

@Test(.requiresMetal4)
@MainActor
func testPointCloud_sizeIsClampedToMaximum() throws {
    let pixels = try render([PointCloudPoint(position: centre, color: white)], pointSize: 200, shape: .square, maximumPointSize: 16)
    #expect(isLit(pixels, at: centre, offset: [6, 0]))
    #expect(!isLit(pixels, at: centre, offset: [12, 0]))
}

@Test(.requiresMetal4)
@MainActor
func testPointCloud_stampsClipAtViewportEdges() throws {
    // A large square centred just outside the left edge must still draw its visible half.
    let edge = SIMD3<Float>(-1.75, 0, 0)
    let pixels = try render([PointCloudPoint(position: edge, color: white)], pointSize: 64, shape: .square)
    let row = pixelCoordinate(of: edge).y
    #expect(max(pixels[row * size.x].x, pixels[row * size.x].y, pixels[row * size.x].z) > 100)
}

// MARK: - Consumer describe functions

// A consumer point layout and describe functions, compiled from source at runtime in their own library.
private let consumerSource = PointCloudShaderSupport.metalSource + """
using namespace metal;

// xyz = position, w = size in pixels.
struct ConsumerPoint {
    float4 positionAndSize;
};

[[visible]] PointCloudSplat greenDiscs(uint index, const device void *points, const device void *userData) {
    float4 point = ((const device ConsumerPoint *)points)[index].positionAndSize;
    return { point.xyz, 0xFF00FF00, point.w, PointCloudShapeDisc };
}

[[visible]] PointCloudSplat colourFromUserData(uint index, const device void *points, const device void *userData) {
    float4 point = ((const device ConsumerPoint *)points)[index].positionAndSize;
    return { point.xyz, ((const device uint *)userData)[0], 1.0, PointCloudShapeSquare };
}
"""

@Test(.requiresMetal4)
@MainActor
func testPointCloud_describeFunctionReadsConsumerLayoutPerPoint() throws {
    let library = try ShaderLibrary(source: consumerSource)
    let describe = PointCloudPointFunction(try library.function(type: VisibleFunction.self, named: "greenDiscs"))
    // Two points with different sizes in the consumer's own layout.
    let small = SIMD3<Float>(-0.5, 0, 0)
    let large = SIMD3<Float>(0.5, 0, 0)
    let points: [SIMD4<Float>] = [SIMD4(small, 3), SIMD4(large, 21)]
    let buffer = try _MTLCreateSystemDefaultDevice().makeBuffer(unsafeBytesOf: points)
    let pixels = try render(buffer: buffer, count: points.count, describe: describe)

    #expect(isLit(pixels, at: large, offset: [8, 0]))
    #expect(!isLit(pixels, at: small, offset: [8, 0]))
    let colour = pixels[pixel(of: large)]
    #expect(colour.y > 200 && colour.z < 50)
}

@Test(.requiresMetal4)
@MainActor
func testPointCloud_describeFunctionReadsUserData() throws {
    let library = try ShaderLibrary(source: consumerSource)
    let device = _MTLCreateSystemDefaultDevice()
    let userData = try device.makeBuffer(unsafeBytesOf: [UInt32(0xFFFF_0000)])
    let describe = PointCloudPointFunction(try library.function(type: VisibleFunction.self, named: "colourFromUserData"), userData: userData)
    let position = SIMD3<Float>(-0.3, -0.2, 0)
    let buffer = try device.makeBuffer(unsafeBytesOf: [SIMD4<Float>(position, 1)])
    let pixels = try render(buffer: buffer, count: 1, describe: describe)
    // 0xFFFF0000 is blue (third byte) at full alpha.
    let bgra = pixels[pixel(of: position)]
    #expect(bgra.x > 200 && bgra.z < 50)
}

@Test
func testPointCloudPoint_packsColorRedInLowestByte() {
    let point = PointCloudPoint(position: .zero, color: [0x11, 0x22, 0x33, 0x44])
    #expect(point.color == 0x4433_2211)
}

@Test
func testPointCloudPoint_isPacked() {
    #expect(MemoryLayout<PointCloudPoint>.stride == 16)
}
