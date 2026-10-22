import CoreGraphics
import Metal
import MetalSprockets
@testable import MetalSprocketsAddOns
import MetalSprocketsSupport
import MetalSupport
import Testing

private let maskSize = 128
private let squareRange = 48..<80

private func makeSquareMask(device: MTLDevice) throws -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: maskSize, height: maskSize, mipmapped: false)
    descriptor.usage = [.shaderRead]
    descriptor.storageMode = .shared
    let texture = try device.makeTexture(descriptor: descriptor).orThrow(.resourceCreationFailure("mask"))
    var pixels = [UInt8](repeating: 0, count: maskSize * maskSize)
    for y in squareRange {
        for x in squareRange {
            pixels[y * maskSize + x] = 255
        }
    }
    texture.replace(region: MTLRegionMake2D(0, 0, maskSize, maskSize), mipmapLevel: 0, withBytes: pixels, bytesPerRow: maskSize)
    return texture
}

@MainActor
private func renderOutline(width: Float) throws -> CGImage {
    let device = _MTLCreateSystemDefaultDevice()
    let mask = try makeSquareMask(device: device)
    let seeds = try JumpFloodPipeline.makeSeedTexture(device: device, width: maskSize, height: maskSize)
    try JumpFloodPipeline(mask: mask, seeds: seeds, maximumDistance: width).run()

    let renderPass = try RenderPass {
        JumpFloodOutlineRenderPipeline(mask: mask, seeds: seeds, color: [1, 1, 1, 1], width: width)
    }
    let renderer = try OffscreenRenderer(size: CGSize(width: maskSize, height: maskSize))
    return try renderer.render(renderPass).cgImage
}

@Test
func testJumpFloodStepSizes() {
    #expect(JumpFloodPipeline.stepSizes(maximumDistance: 1) == [1])
    #expect(JumpFloodPipeline.stepSizes(maximumDistance: 10) == [8, 4, 2, 1])
    #expect(JumpFloodPipeline.stepSizes(maximumDistance: 40) == [32, 16, 8, 4, 2, 1])
}

@Test(.requiresMetal4)
@MainActor
func testJumpFloodOutline_coversWidthAroundMask() throws {
    let image = try renderOutline(width: 10)
    let right = squareRange.upperBound
    #expect(try image.luminance(atX: right + 4, y: 64) > 0.99)
    #expect(try image.luminance(atX: right + 15, y: 64) < 0.01)
    #expect(try image.luminance(atX: 64, y: 64) < 0.01, "Inside of the mask is left unchanged")
    // Diagonal from the corner: ~7 px away is inside, ~14 px is outside.
    #expect(try image.luminance(atX: right + 4, y: squareRange.upperBound + 4) > 0.99)
    #expect(try image.luminance(atX: right + 10, y: squareRange.upperBound + 10) < 0.01)
}

@Test(.requiresMetal4)
@MainActor
func testJumpFloodOutline_wideOutline() throws {
    let image = try renderOutline(width: 40)
    let left = squareRange.lowerBound
    #expect(try image.luminance(atX: left - 35, y: 64) > 0.99)
    #expect(try image.luminance(atX: left - 45, y: 64) < 0.01)
    #expect(try image.luminance(atX: 64, y: squareRange.lowerBound - 35) > 0.99)
}

/// A square mask at depth 0.5, in the RG layout `SilhouetteMaskRenderPipeline` writes.
private func makeSquareDepthMask(device: MTLDevice) throws -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg32Float, width: maskSize, height: maskSize, mipmapped: false)
    descriptor.usage = [.shaderRead]
    descriptor.storageMode = .shared
    let texture = try device.makeTexture(descriptor: descriptor).orThrow(.resourceCreationFailure("mask"))
    var pixels = [SIMD2<Float>](repeating: .zero, count: maskSize * maskSize)
    for y in squareRange {
        for x in squareRange {
            pixels[y * maskSize + x] = [1, 0.5]
        }
    }
    texture.replace(region: MTLRegionMake2D(0, 0, maskSize, maskSize), mipmapLevel: 0, withBytes: pixels, bytesPerRow: maskSize * MemoryLayout<SIMD2<Float>>.stride)
    return texture
}

@Test(.requiresMetal4)
@MainActor
func testJumpFloodOutline_depthTestUsesMaskDepth() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let mask = try makeSquareDepthMask(device: device)
    let seeds = try JumpFloodPipeline.makeSeedTexture(device: device, width: maskSize, height: maskSize)
    try JumpFloodPipeline(mask: mask, seeds: seeds, maximumDistance: 10).run()

    // The cleared depth stands in for the scene: 1 is behind the mask's 0.5, 0.25 is in front of it.
    func render(sceneDepth: Double) throws -> CGImage {
        let renderPass = try RenderPass {
            JumpFloodOutlineRenderPipeline(mask: mask, seeds: seeds, color: [1, 1, 1, 1], width: 10, depthCompareFunction: .lessEqual)
        }
        let renderer = try OffscreenRenderer(size: CGSize(width: maskSize, height: maskSize))
        renderer.renderPassDescriptor.depthAttachment.clearDepth = sceneDepth
        return try renderer.render(renderPass).cgImage
    }
    let x = squareRange.upperBound + 4
    #expect(try render(sceneDepth: 1).luminance(atX: x, y: 64) > 0.99)
    #expect(try render(sceneDepth: 0.25).luminance(atX: x, y: 64) < 0.01)
}
