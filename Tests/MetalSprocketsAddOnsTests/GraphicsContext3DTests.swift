// GraphicsContext3D + GraphicsContext3DRenderPipeline golden-image tests.
// These tests exercise GraphicsContext3D, Path3D, StrokeStyle, GeometryGenerator,
// and GraphicsContext3DRenderPipeline together.

import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
@testable import MetalSprocketsAddOns
import MetalSprocketsSupport
import simd
import SwiftUI
import Testing

@Test
@MainActor
func testGraphicsContext3D_axisCross() throws {
    let projection = perspectiveProjection()
    let camera = float4x4(simd_quatf(angle: -.pi / 5, axis: SIMD3<Float>(1, 1, 0))) * float4x4(translation: SIMD3<Float>(0, 0, 4))
    let viewProjection = projection * camera.inverse
    let viewport = SIMD2<Float>(Float(defaultRenderSize.width), Float(defaultRenderSize.height))

    let context = GraphicsContext3D { ctx in
        ctx.stroke(
            Path3D { path in
                path.move(to: [-1, 0, 0])
                path.addLine(to: [1, 0, 0])
            },
            with: .red,
            lineWidth: 4
        )
        ctx.stroke(
            Path3D { path in
                path.move(to: [0, -1, 0])
                path.addLine(to: [0, 1, 0])
            },
            with: .green,
            lineWidth: 4
        )
        ctx.stroke(
            Path3D { path in
                path.move(to: [0, 0, -1])
                path.addLine(to: [0, 0, 1])
            },
            with: .blue,
            lineWidth: 4
        )
    }

    let renderPass = try RenderPass {
        GraphicsContext3DRenderPipeline(
            context: context,
            viewProjection: viewProjection,
            viewport: viewport
        )
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "GraphicsContext3DAxisCross"))
}

@Test
@MainActor
func testGraphicsContext3D_strokedTriangleWithRoundCaps() throws {
    let projection = perspectiveProjection()
    let camera = float4x4(translation: SIMD3<Float>(0, 0, 3))
    let viewProjection = projection * camera.inverse
    let viewport = SIMD2<Float>(Float(defaultRenderSize.width), Float(defaultRenderSize.height))

    let context = GraphicsContext3D { ctx in
        let style = StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
        ctx.stroke(
            Path3D { path in
                path.move(to: [-0.6, -0.5, 0])
                path.addLine(to: [0.6, -0.5, 0])
                path.addLine(to: [0, 0.7, 0])
                path.closeSubpath()
            },
            with: .yellow,
            style: style
        )
    }

    let renderPass = try RenderPass {
        GraphicsContext3DRenderPipeline(
            context: context,
            viewProjection: viewProjection,
            viewport: viewport
        )
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "GraphicsContext3DTriangle"))
}

@Test
@MainActor
func testGraphicsContext3D_filledQuad() throws {
    let projection = perspectiveProjection()
    let camera = float4x4(translation: SIMD3<Float>(0, 0, 3))
    let viewProjection = projection * camera.inverse
    let viewport = SIMD2<Float>(Float(defaultRenderSize.width), Float(defaultRenderSize.height))

    let context = GraphicsContext3D { ctx in
        ctx.fill(
            Path3D { path in
                path.move(to: [-0.6, -0.6, 0])
                path.addLine(to: [0.6, -0.6, 0])
                path.addLine(to: [0.6, 0.6, 0])
                path.addLine(to: [-0.6, 0.6, 0])
                path.closeSubpath()
            },
            with: .cyan
        )
    }

    let renderPass = try RenderPass {
        GraphicsContext3DRenderPipeline(
            context: context,
            viewProjection: viewProjection,
            viewport: viewport
        )
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "GraphicsContext3DFilledQuad"))
}
