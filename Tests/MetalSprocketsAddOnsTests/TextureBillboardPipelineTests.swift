// TextureBillboardPipeline golden-image tests. Also exercises ColorSource and
// SimpleStitchedFunctionGraph indirectly.

import CoreGraphics
import Metal
import MetalSprockets
@testable import MetalSprocketsAddOns
import MetalSprocketsSupport
import MetalSupport
import simd
import Testing

@Test
@MainActor
func testTextureBillboardPipeline_checkerboard() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let texture = try makeCheckerboardTexture(device: device, size: 16)

    let renderPass = try RenderPass {
        try TextureBillboardPipeline(specifier: ColorSource.texture2D(texture))
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "TextureBillboardCheckerboard"))
}

@Test
@MainActor
func testTextureBillboardPipeline_solidColorSpecifier() throws {
    // Use a solid colored ColorSource as specifierA — exercises the .color path through ColorSource.
    let renderPass = try RenderPass {
        try TextureBillboardPipeline(specifier: ColorSource.color([0.2, 0.6, 0.9]))
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "TextureBillboardSolid"))
}

@Test
@MainActor
func testTextureBillboardPipeline_initWithColorTransformFunctionName() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let texture = try makeCheckerboardTexture(device: device, size: 16)

    // Should resolve `colorTransformIdentity` from the shader bundle.
    let renderPass = try RenderPass {
        try TextureBillboardPipeline(
            specifierA: ColorSource.texture2D(texture),
            specifierB: ColorSource.color([0, 0, 0]),
            colorTransformFunctionName: "colorTransformIdentity"
        )
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    _ = try renderer.render(renderPass)
}

@Test
@MainActor
func testTextureBillboardPipeline_initWithCustomTextureCoordinatesArray() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let texture = try makeCheckerboardTexture(device: device, size: 16)

    let coords: [SIMD2<Float>] = [
        [0, 1],
        [1, 1],
        [0, 0],
        [1, 0]
    ]
    let renderPass = try RenderPass {
        try TextureBillboardPipeline(
            specifierA: ColorSource.texture2D(texture),
            specifierB: ColorSource.color([0, 0, 0]),
            textureCoordinatesArray: coords,
            colorTransformFunctionName: "colorTransformIdentity"
        )
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    _ = try renderer.render(renderPass)
}

@Test
@MainActor
func testTextureBillboardPipeline_partialQuad() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let texture = try makeCheckerboardTexture(device: device, size: 16)

    // Render a quad covering only the upper-right portion of the screen.
    let renderPass = try RenderPass {
        try TextureBillboardPipeline(
            specifier: ColorSource.texture2D(texture),
            positions: Quad(min: [0, 0], max: [1, 1])
        )
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "TextureBillboardPartial"))
}
