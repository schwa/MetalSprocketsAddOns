// GraphicsContext3D + GraphicsContext3DRenderPipeline golden-image tests.
// These tests exercise GraphicsContext3D, Path3D, StrokeStyle, GeometryGenerator,
// and GraphicsContext3DRenderPipeline together.

import CoreGraphics
import Foundation
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
func testGraphicsContext3D_strokeStyles_capsAndJoins() throws {
    // Exercise every cap (.butt, .round, .square) and join (.miter, .round, .bevel)
    // combination plus quad and cubic curves to cover GeometryGenerator's branches.
    let projection = perspectiveProjection()
    let camera = float4x4(translation: SIMD3<Float>(0, 0, 3))
    let viewProjection = projection * camera.inverse
    let viewport = SIMD2<Float>(Float(defaultRenderSize.width), Float(defaultRenderSize.height))

    let context = GraphicsContext3D { ctx in
        // Open polylines with each cap style.
        let caps: [(CGLineCap, Float)] = [(.butt, -0.6), (.round, 0), (.square, 0.6)]
        for (cap, x) in caps {
            let style = StrokeStyle(lineWidth: 6, lineCap: cap, lineJoin: .miter)
            ctx.stroke(
                Path3D { p in
                    p.move(to: [x - 0.1, -0.6, 0])
                    p.addLine(to: [x + 0.1, -0.6, 0])
                },
                with: .white,
                style: style
            )
        }

        // Closed paths with each join style.
        let joins: [(CGLineJoin, Float)] = [(.miter, -0.6), (.round, 0), (.bevel, 0.6)]
        for (join, x) in joins {
            let style = StrokeStyle(lineWidth: 4, lineCap: .butt, lineJoin: join, miterLimit: 4)
            ctx.stroke(
                Path3D { p in
                    p.move(to: [x - 0.15, 0, 0])
                    p.addLine(to: [x + 0.15, 0.15, 0])
                    p.addLine(to: [x + 0.15, -0.15, 0])
                    p.closeSubpath()
                },
                with: .yellow,
                style: style
            )
        }

        // Quad curve.
        ctx.stroke(
            Path3D { p in
                p.move(to: [-0.6, 0.5, 0])
                p.addQuadCurve(to: [0, 0.8, 0], control: [-0.3, 0.95, 0])
            },
            with: .cyan,
            lineWidth: 3
        )

        // Cubic curve.
        ctx.stroke(
            Path3D { p in
                p.move(to: [0, 0.5, 0])
                p.addCurve(to: [0.6, 0.5, 0], control1: [0.2, 0.9, 0], control2: [0.4, 0.1, 0])
            },
            with: .green,
            lineWidth: 3
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
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "GraphicsContext3DCapsJoins"))
}

@Test
@MainActor
func testGraphicsContext3D_debugWireframe() throws {
    let projection = perspectiveProjection()
    let camera = float4x4(translation: SIMD3<Float>(0, 0, 3))
    let viewProjection = projection * camera.inverse
    let viewport = SIMD2<Float>(Float(defaultRenderSize.width), Float(defaultRenderSize.height))

    let context = GraphicsContext3D { ctx in
        let style = StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
        ctx.stroke(
            Path3D { p in
                p.move(to: [-0.4, -0.4, 0])
                p.addLine(to: [0.4, -0.4, 0])
                p.addLine(to: [0, 0.4, 0])
                p.closeSubpath()
            },
            with: .blue,
            style: style
        )
    }

    let renderPass = try RenderPass {
        GraphicsContext3DRenderPipeline(
            context: context,
            viewProjection: viewProjection,
            viewport: viewport,
            debugWireframe: true
        )
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "GraphicsContext3DDebugWireframe"))
}

// Fill + stroke an ellipse — the stroke outline makes the filled shape's
// boundary visible, exercising the .quadCurve branch in both
// `generateFillGeometry` and `generateLineJoinGPUData`.
//
// Approximate a unit ellipse using four quadratic Bezier segments
// (a common 4-arc approximation, control offset = 4(√2 - 1)/3 ≈ 0.5523).
private func ellipsePath(centerX: Float = 0, centerY: Float = 0, rx: Float = 0.5, ry: Float = 0.5) -> Path3D {
    let k: Float = 0.5522847498  // (4/3) * tan(pi/8)
    let cx = centerX
    let cy = centerY
    return Path3D { p in
        // Start at right (cx + rx, cy)
        p.move(to: [cx + rx, cy, 0])
        // Top-right arc to top.
        p.addQuadCurve(to: [cx, cy + ry, 0], control: [cx + rx, cy + ry * k, 0])
        // Top-left arc to left.
        p.addQuadCurve(to: [cx - rx, cy, 0], control: [cx - rx * k, cy + ry, 0])
        // Bottom-left arc to bottom.
        p.addQuadCurve(to: [cx, cy - ry, 0], control: [cx - rx, cy - ry * k, 0])
        // Bottom-right arc back to start.
        p.addQuadCurve(to: [cx + rx, cy, 0], control: [cx + rx * k, cy - ry, 0])
        p.closeSubpath()
    }
}

@Test
@MainActor
func testGraphicsContext3D_strokedEllipse() throws {
    // Stroke an ellipse path so the bezier curve approximation is clearly
    // visible. Filled-with-curves rendering is exercised separately by the
    // existing testGraphicsContext3D_filledQuad test (line-only fill).
    let projection = perspectiveProjection()
    let camera = float4x4(translation: SIMD3<Float>(0, 0, 3))
    let viewProjection = projection * camera.inverse
    let viewport = SIMD2<Float>(Float(defaultRenderSize.width), Float(defaultRenderSize.height))

    let path = ellipsePath(rx: 0.55, ry: 0.4)
    let context = GraphicsContext3D { ctx in
        ctx.stroke(
            path,
            with: .orange,
            style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
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
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "GraphicsContext3DStrokedEllipse"))
}

// FIXME: This test crashes on GitHub Actions macOS runners (paravirt GPU) with
// `-[AppleParavirtRenderCommandEncoder setMeshBuffer:offset:atIndex:]:
// unrecognized selector`. The crash aborts the entire test process. Disabled on
// CI until investigated. See issue #29.
@Test(.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil, "Crashes on CI paravirt GPU — see issue #29"))
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
