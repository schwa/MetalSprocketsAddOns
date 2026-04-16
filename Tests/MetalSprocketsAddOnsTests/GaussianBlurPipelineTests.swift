// GaussianBlurPipeline Unit Tests
//
// Renders a simple pattern into a texture, applies the Gaussian blur pipeline,
// and compares the output against a golden reference image.
//
//   just test-one GaussianBlur

#if canImport(MetalPerformanceShaders)
import CoreGraphics
import Metal
import MetalPerformanceShaders
import MetalSprockets
@testable import MetalSprocketsAddOns
import MetalSprocketsSupport
import MetalSupport
import Testing

@Test
@MainActor
func testGaussianBlurPipeline_softensStarkPattern() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let size = 128

    let source = try makeWhiteSquareTexture(device: device, size: size)
    let destination = try makeEmptyBGRA8Texture(device: device, size: size, usage: [.shaderWrite, .shaderRead])

    let pipeline = GaussianBlurPipeline(source: source, destination: destination, sigma: 6.0)
    let element = CommandBufferElement(completion: .commitAndWaitUntilCompleted) {
        pipeline
    }
    try element.run()

    let image = try destination.toCGImage()
    #expect(try image.isEqualToGoldenImage(named: "GaussianBlurSquare"))
}

// MARK: - Helpers

private func makeEmptyBGRA8Texture(
    device: MTLDevice,
    size: Int,
    usage: MTLTextureUsage
) throws -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: size,
        height: size,
        mipmapped: false
    )
    descriptor.usage = usage
    descriptor.storageMode = .shared
    return try device.makeTexture(descriptor: descriptor)
        .orThrow(.resourceCreationFailure("Failed to create texture"))
}

/// A black texture with a solid white square in the center.
private func makeWhiteSquareTexture(device: MTLDevice, size: Int) throws -> MTLTexture {
    let texture = try makeEmptyBGRA8Texture(device: device, size: size, usage: [.shaderRead])

    // BGRA8: byte order is B, G, R, A
    var pixels = [UInt8](repeating: 0, count: size * size * 4)
    // Make everything fully opaque (alpha = 255)
    for y in 0..<size {
        for x in 0..<size {
            let offset = (y * size + x) * 4
            pixels[offset + 3] = 255
        }
    }
    let squareSize = size / 4
    let lo = (size - squareSize) / 2
    let hi = lo + squareSize
    for y in lo..<hi {
        for x in lo..<hi {
            let offset = (y * size + x) * 4
            pixels[offset + 0] = 255 // B
            pixels[offset + 1] = 255 // G
            pixels[offset + 2] = 255 // R
            pixels[offset + 3] = 255 // A
        }
    }
    let region = MTLRegionMake2D(0, 0, size, size)
    texture.replace(region: region, mipmapLevel: 0, withBytes: pixels, bytesPerRow: size * 4)
    return texture
}
#endif
