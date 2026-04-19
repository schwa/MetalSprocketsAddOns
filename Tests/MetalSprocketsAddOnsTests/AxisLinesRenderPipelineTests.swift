// AxisLinesRenderPipeline golden-image tests.

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
func testAxisLinesRenderPipeline_default() throws {
    let projection = perspectiveProjection()
    let camera = float4x4(simd_quatf(angle: -.pi / 6, axis: SIMD3<Float>(1, 0, 0))) * float4x4(translation: SIMD3<Float>(0, 0, 5))
    let viewMatrix = camera.inverse
    let mvp = projection * viewMatrix
    let viewport = SIMD2<Float>(Float(defaultRenderSize.width), Float(defaultRenderSize.height))

    let renderPass = try RenderPass {
        try AxisLinesRenderPipeline(
            mvpMatrix: mvp,
            viewMatrix: viewMatrix,
            projectionMatrix: projection,
            viewportSize: viewport,
            lineWidth: 4.0
        )
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "AxisLinesDefault"))
}

@Test
@MainActor
func testAxisLinesRenderPipeline_customColors() throws {
    let projection = perspectiveProjection()
    let camera = float4x4(simd_quatf(angle: -.pi / 5, axis: SIMD3<Float>(1, 0.4, 0))) * float4x4(translation: SIMD3<Float>(0, 0, 6))
    let viewMatrix = camera.inverse
    let mvp = projection * viewMatrix
    let viewport = SIMD2<Float>(Float(defaultRenderSize.width), Float(defaultRenderSize.height))

    let renderPass = try RenderPass {
        try AxisLinesRenderPipeline(
            mvpMatrix: mvp,
            viewMatrix: viewMatrix,
            projectionMatrix: projection,
            viewportSize: viewport,
            lineWidth: 6.0,
            xAxisColor: [1, 1, 0, 1],
            yAxisColor: [0, 1, 1, 1],
            zAxisColor: [1, 0, 1, 1]
        )
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "AxisLinesCustomColors"))
}
