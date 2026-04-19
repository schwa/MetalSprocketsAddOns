// TexturedQuad3DPipeline golden-image tests.
// Uses Mandrill YCbCr fixtures (mirrored from MetalSprockets) to drive the
// TexturedQuad3D pipeline's two-plane (Y + CbCr) sampler path.

import CoreGraphics
import Foundation
import GeometryLite3D
import ImageIO
import Metal
import MetalSprockets
@testable import MetalSprocketsAddOns
import MetalSprocketsSupport
import MetalSupport
import simd
import Testing

// MARK: - YCbCr fixture helpers (adapted from MetalSprockets YCbCrBillboardRenderPassTests)

private func loadFixturePNG(named name: String) throws -> CGImage {
    let url = try #require(
        Bundle.module.url(forResource: "Fixtures/Mandrill/\(name)", withExtension: "png")
    )
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
}

private func makeR8Texture(from cgImage: CGImage, device: MTLDevice) throws -> MTLTexture {
    let width = cgImage.width
    let height = cgImage.height
    var bytes = [UInt8](repeating: 0, count: width * height)
    let context = try #require(CGContext(
        data: &bytes,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
    ))
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    let desc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .r8Unorm,
        width: width,
        height: height,
        mipmapped: false
    )
    desc.usage = [.shaderRead]
    desc.storageMode = .shared
    let texture = try #require(device.makeTexture(descriptor: desc))
    bytes.withUnsafeBufferPointer { buf in
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: buf.baseAddress!,
            bytesPerRow: width
        )
    }
    return texture
}

private func makeRG8Texture(from cgImage: CGImage, device: MTLDevice) throws -> MTLTexture {
    let width = cgImage.width
    let height = cgImage.height
    var rgba = [UInt8](repeating: 0, count: width * height * 4)
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    let context = try #require(CGContext(
        data: &rgba,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo
    ))
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    var rg = [UInt8](repeating: 0, count: width * height * 2)
    for i in 0..<(width * height) {
        rg[i * 2 + 0] = rgba[i * 4 + 0]  // Cb (R channel)
        rg[i * 2 + 1] = rgba[i * 4 + 1]  // Cr (G channel)
    }

    let desc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rg8Unorm,
        width: width,
        height: height,
        mipmapped: false
    )
    desc.usage = [.shaderRead]
    desc.storageMode = .shared
    let texture = try #require(device.makeTexture(descriptor: desc))
    rg.withUnsafeBufferPointer { buf in
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: buf.baseAddress!,
            bytesPerRow: width * 2
        )
    }
    return texture
}

// MARK: - Tests

// YCbCr texture sampling returns green on the CI paravirt GPU — see issue #29.
@Test(.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil, "Texture sampling broken on CI paravirt GPU — see issue #29"))
@MainActor
func testTexturedQuad3DPipeline_mandrillFlat() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let textureY = try makeR8Texture(from: try loadFixturePNG(named: "mandrill_Y"), device: device)
    let textureCbCr = try makeRG8Texture(from: try loadFixturePNG(named: "mandrill_CbCr"), device: device)

    // Identity MVP — quad fills clip space.
    let mvp = matrix_identity_float4x4
    let vertices: [SIMD3<Float>] = [
        [-1, -1, 0],
        [1, -1, 0],
        [-1, 1, 0],
        [1, 1, 0]
    ]
    let textureCoords: [SIMD2<Float>] = [
        [0, 1],
        [1, 1],
        [0, 0],
        [1, 0]
    ]

    let renderPass = try RenderPass {
        TexturedQuad3DPipeline(
            vertices: vertices,
            textureCoords: textureCoords,
            textureY: textureY,
            textureCbCr: textureCbCr,
            mvpMatrix: mvp
        )
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "TexturedQuad3DMandrill"))
}

@Test(.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil, "Texture sampling broken on CI paravirt GPU — see issue #29"))
@MainActor
func testTexturedQuad3DPipeline_mandrillRotatedInPerspective() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let textureY = try makeR8Texture(from: try loadFixturePNG(named: "mandrill_Y"), device: device)
    let textureCbCr = try makeRG8Texture(from: try loadFixturePNG(named: "mandrill_CbCr"), device: device)

    let projection = perspectiveProjection()
    let camera = float4x4(translation: SIMD3<Float>(0, 0, 2.5))
    let model = float4x4(simd_quatf(angle: .pi / 6, axis: SIMD3<Float>(0, 1, 0)))
    let mvp = projection * camera.inverse * model

    let vertices: [SIMD3<Float>] = [
        [-1, -1, 0],
        [1, -1, 0],
        [-1, 1, 0],
        [1, 1, 0]
    ]
    let textureCoords: [SIMD2<Float>] = [
        [0, 1],
        [1, 1],
        [0, 0],
        [1, 0]
    ]

    let renderPass = try RenderPass {
        TexturedQuad3DPipeline(
            vertices: vertices,
            textureCoords: textureCoords,
            textureY: textureY,
            textureCbCr: textureCbCr,
            mvpMatrix: mvp
        )
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "TexturedQuad3DMandrillRotated"))
}
