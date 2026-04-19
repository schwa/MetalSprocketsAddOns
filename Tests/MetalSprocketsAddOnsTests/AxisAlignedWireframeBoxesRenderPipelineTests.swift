// AxisAlignedWireframeBoxesRenderPipeline golden-image tests.

import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
@testable import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import simd
import Testing

@Test
@MainActor
func testAxisAlignedWireframeBoxes_singleBox() throws {
    let projection = perspectiveProjection()
    let camera = float4x4(simd_quatf(angle: -.pi / 5, axis: SIMD3<Float>(1, 1, 0))) * float4x4(translation: SIMD3<Float>(0, 0, 4))
    let mvp = projection * camera.inverse

    let boxes = [
        BoxInstance(min: [-1, -1, -1], max: [1, 1, 1], color: [1, 1, 1, 1])
    ]

    let renderPass = try RenderPass {
        AxisAlignedWireframeBoxesRenderPipeline(mvpMatrix: mvp, boxes: boxes)
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "AxisAlignedWireframeBoxesSingle"))
}

@Test
@MainActor
func testAxisAlignedWireframeBoxes_multipleColored() throws {
    let projection = perspectiveProjection()
    let camera = float4x4(simd_quatf(angle: -.pi / 5, axis: SIMD3<Float>(1, 0.5, 0))) * float4x4(translation: SIMD3<Float>(0, 0, 6))
    let mvp = projection * camera.inverse

    let boxes = [
        BoxInstance(min: [-1.5, -0.5, -0.5], max: [-0.5, 0.5, 0.5], color: [1, 0, 0, 1]),
        BoxInstance(min: [-0.5, -0.5, -0.5], max: [0.5, 0.5, 0.5], color: [0, 1, 0, 1]),
        BoxInstance(min: [0.5, -0.5, -0.5], max: [1.5, 0.5, 0.5], color: [0, 0, 1, 1])
    ]

    let renderPass = try RenderPass {
        AxisAlignedWireframeBoxesRenderPipeline(mvpMatrix: mvp, boxes: boxes)
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "AxisAlignedWireframeBoxesMulti"))
}
