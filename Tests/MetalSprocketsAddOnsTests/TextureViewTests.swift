import CoreGraphics
import Metal
@testable import MetalSprocketsAddOnsUI
import MetalSupport
import Testing

private func makeTexture(device: MTLDevice, bgra: [UInt8]) throws -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
    descriptor.storageMode = .shared
    let texture = try #require(device.makeTexture(descriptor: descriptor))
    texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: bgra, bytesPerRow: 4)
    return texture
}

private func firstPixel(_ image: CGImage) throws -> [UInt8] {
    let data = try #require(image.dataProvider?.data as Data?)
    return Array(data.prefix(4))
}

@Test
func testImageCache_forgetsFreedTexture() throws {
    // Issue #77: once the cached texture is freed, nothing can match the cached image.
    let device = _MTLCreateSystemDefaultDevice()
    let cache = ImageCache()
    autoreleasepool {
        let texture = try? makeTexture(device: device, bgra: [0, 0, 255, 255])
        _ = cache.image(for: texture)
        #expect(cache.cachedTexture != nil)
    }
    #expect(cache.cachedTexture == nil)
}

@Test
func testImageCache_cachesWhileTextureIsAlive() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let cache = ImageCache()
    let texture = try makeTexture(device: device, bgra: [0, 0, 255, 255])
    let first = try #require(cache.image(for: texture))
    let second = try #require(cache.image(for: texture))
    #expect(first === second)
}

/// Best effort: whether a freed address is reused depends on the allocator (for example, it is
/// reused at once with Metal API validation on, and not reliably without it). When it is not
/// reused, the test has nothing to check and returns.
@Test
func testImageCache_doesNotReuseImageForNewTextureAtFreedAddress() throws {
    // Issue #77: the cache was keyed on ObjectIdentifier. A new texture allocated at a freed
    // texture's address got the old texture's image.
    let device = _MTLCreateSystemDefaultDevice()
    let cache = ImageCache()
    // Metal returns autoreleased objects, so drain a pool to actually free the red texture.
    let freedAddress = try autoreleasepool {
        let red = try makeTexture(device: device, bgra: [0, 0, 255, 255])
        _ = cache.image(for: red)
        return ObjectIdentifier(red)
    }

    // Allocate and free until a texture lands on the freed address (within a few tries in practice).
    var blue: MTLTexture?
    for _ in 0..<1_000 {
        let candidate = try autoreleasepool { try makeTexture(device: device, bgra: [255, 0, 0, 255]) }
        if ObjectIdentifier(candidate) == freedAddress {
            blue = candidate
            break
        }
    }
    guard let reused = blue else {
        return
    }
    let image = try #require(cache.image(for: reused))
    let pixel = try firstPixel(image)
    // BGRA: blue channel set, red channel clear.
    #expect(pixel[0] == 255 && pixel[2] == 0)
}
