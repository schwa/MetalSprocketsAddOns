// EquirectangularSkyboxRenderPipeline golden-image tests.

import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
@testable import MetalSprocketsAddOns
import MetalSprocketsSupport
import MetalSupport
import simd
import Testing

@Test
@MainActor
func testEquirectangularSkyboxRenderPipeline_default() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let panoramaTexture = try makeGradientEquirectangularTexture(device: device)

    let projection = perspectiveProjection()
    // Camera at origin so the skybox fills the view
    let camera = float4x4(translation: SIMD3<Float>(0, 0, 0))

    let renderPass = try RenderPass {
        try EquirectangularSkyboxRenderPipeline(
            projectionMatrix: projection,
            cameraMatrix: camera,
            texture: panoramaTexture
        )
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "EquirectangularSkyboxDefault"))
}

@Test
@MainActor
func testEquirectangularSkyboxRenderPipeline_rotated() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let panoramaTexture = try makeGradientEquirectangularTexture(device: device)

    let projection = perspectiveProjection()
    let camera = float4x4(simd_quatf(angle: .pi / 8, axis: SIMD3<Float>(0, 1, 0)))

    let renderPass = try RenderPass {
        try EquirectangularSkyboxRenderPipeline(
            projectionMatrix: projection,
            cameraMatrix: camera,
            rotation: simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 1, 0)),
            texture: panoramaTexture
        )
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "EquirectangularSkyboxRotated"))
}
