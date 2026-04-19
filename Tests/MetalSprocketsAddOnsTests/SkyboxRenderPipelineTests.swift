// SkyboxRenderPipeline golden-image tests.

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
func testSkyboxRenderPipeline_solidFaces() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let cubeTexture = try makeGradientCubeTexture(device: device)

    let projection = perspectiveProjection()
    // Camera near origin so the skybox dominates the view
    let camera = float4x4(translation: SIMD3<Float>(0, 0, 0))

    let renderPass = try RenderPass {
        try SkyboxRenderPipeline(
            projectionMatrix: projection,
            cameraMatrix: camera,
            texture: cubeTexture
        )
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "SkyboxSolidFaces"))
}

@Test
@MainActor
func testSkyboxRenderPipeline_rotated() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let cubeTexture = try makeGradientCubeTexture(device: device)

    let projection = perspectiveProjection()
    let camera = float4x4(simd_quatf(angle: .pi / 8, axis: SIMD3<Float>(0, 1, 0)))

    let renderPass = try RenderPass {
        try SkyboxRenderPipeline(
            projectionMatrix: projection,
            cameraMatrix: camera,
            rotation: simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 1, 0)),
            texture: cubeTexture
        )
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "SkyboxRotated"))
}
