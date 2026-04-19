// WireframeRenderPipeline golden-image tests.

import CoreGraphics
import GeometryLite3D
import Metal
import MetalKit
import MetalSprockets
@testable import MetalSprocketsAddOns
import MetalSprocketsSupport
import MetalSupport
import simd
import Testing

@Test
@MainActor
func testWireframeRenderPipeline_box() throws {
    let mesh = MTKMesh.box(extent: [1, 1, 1])

    let projection = perspectiveProjection()
    let camera = lookAtOriginCameraMatrix(distance: 3.0)
    let model = float4x4(simd_quatf(angle: .pi / 6, axis: SIMD3<Float>(1, 1, 0)))
    let mvp = projection * camera.inverse * model

    let renderPass = try RenderPass {
        WireframeRenderPipeline(
            mvpMatrix: mvp,
            wireframeColor: [1, 1, 1, 1],
            mesh: mesh
        )
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "WireframeBox"))
}

@Test
@MainActor
func testWireframeRenderPipeline_sphere() throws {
    let mesh = MTKMesh.sphere(extent: [1, 1, 1])

    let projection = perspectiveProjection()
    let camera = lookAtOriginCameraMatrix(distance: 3.0)
    let mvp = projection * camera.inverse

    let renderPass = try RenderPass {
        WireframeRenderPipeline(
            mvpMatrix: mvp,
            wireframeColor: [0, 1, 0, 1],
            mesh: mesh
        )
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "WireframeSphere"))
}
