// GridShader golden-image tests.

import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
@testable import MetalSprocketsAddOns
import MetalSprocketsSupport
import simd
import Testing

@Test
@MainActor
func testGridShader_default() throws {
    let projection = perspectiveProjection()
    // Look down at the grid from above and angled
    let camera = float4x4(translation: SIMD3<Float>(0, 4, 6)) * float4x4(simd_quatf(angle: -.pi / 4, axis: SIMD3<Float>(1, 0, 0)))

    let renderPass = try RenderPass {
        GridShader(
            projectionMatrix: projection,
            cameraMatrix: camera
        )
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "GridShaderDefault"))
}

@Test
@MainActor
func testGridShader_withMajorDivisionAndHighlight() throws {
    let projection = perspectiveProjection()
    let camera = float4x4(translation: SIMD3<Float>(0, 5, 8)) * float4x4(simd_quatf(angle: -.pi / 3.5, axis: SIMD3<Float>(1, 0, 0)))

    let renderPass = try RenderPass {
        GridShader(
            projectionMatrix: projection,
            cameraMatrix: camera,
            gridColor: [0.7, 0.7, 0.9, 1],
            backgroundColor: [0.05, 0.05, 0.1, 1],
            highlightedLines: [
                .init(axis: .x, position: 0, width: 0.05, color: [1, 0, 0, 1]),
                .init(axis: .y, position: 0, width: 0.05, color: [0, 1, 0, 1])
            ],
            majorDivision: .init(interval: 5, lineWidth: [0.03, 0.03], color: [1, 1, 1, 1])
        )
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "GridShaderMajorDivision"))
}
