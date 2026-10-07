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

@Test(.requiresMetal4, .disabled(if: !supportsMeshShaders, "Stroking needs mesh shaders — see issue #29"))
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

@Test(.requiresMetal4, .disabled(if: !supportsMeshShaders, "Stroking needs mesh shaders — see issue #29"))
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

@Test(.requiresMetal4, .disabled(if: !supportsMeshShaders, "Stroking needs mesh shaders — see issue #29"))
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

@Test(.requiresMetal4, .disabled(if: !supportsMeshShaders, "Stroking needs mesh shaders — see issue #29"))
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
// Approximate an ellipse using four cubic Bezier segments (the standard 4-arc
// approximation, control offset k = 4(√2 - 1)/3 ≈ 0.5523). k is a *cubic*
// constant: feeding it to addQuadCurve leaves a tangent discontinuity at every
// quadrant, which renders as a lemon-shaped blob with four corners (issue #25).
func ellipsePath(centerX: Float = 0, centerY: Float = 0, rx: Float = 0.5, ry: Float = 0.5) -> Path3D {
    let k: Float = 0.5522847498
    let cx = centerX
    let cy = centerY
    return Path3D { p in
        // Start at right (cx + rx, cy)
        p.move(to: [cx + rx, cy, 0])
        // Top-right arc to top.
        p.addCurve(to: [cx, cy + ry, 0], control1: [cx + rx, cy + ry * k, 0], control2: [cx + rx * k, cy + ry, 0])
        // Top-left arc to left.
        p.addCurve(to: [cx - rx, cy, 0], control1: [cx - rx * k, cy + ry, 0], control2: [cx - rx, cy + ry * k, 0])
        // Bottom-left arc to bottom.
        p.addCurve(to: [cx, cy - ry, 0], control1: [cx - rx, cy - ry * k, 0], control2: [cx - rx * k, cy - ry, 0])
        // Bottom-right arc back to start.
        p.addCurve(to: [cx + rx, cy, 0], control1: [cx + rx * k, cy - ry, 0], control2: [cx + rx, cy - ry * k, 0])
        p.closeSubpath()
    }
}

@Test(.requiresMetal4, .disabled(if: !supportsMeshShaders, "Stroking needs mesh shaders — see issue #29"))
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

@Test(.requiresMetal4, .disabled(if: !supportsMeshShaders, "Stroking needs mesh shaders — see issue #29"))
@MainActor
func testGraphicsContext3D_strokeWidthIsUniformAlongCurves() throws {
    // Regression test for issue #26. A stroked circle must come out as a ring of
    // constant radial thickness; anything else means the stroke width drifts
    // along the curve.
    let renderSize = CGSize(width: 512, height: 512)
    let projection = perspectiveProjection()
    let camera = float4x4(translation: SIMD3<Float>(0, 0, 3))
    let viewProjection = projection * camera.inverse
    let viewport = SIMD2<Float>(Float(renderSize.width), Float(renderSize.height))

    let lineWidth: Float = 6
    let context = GraphicsContext3D { ctx in
        ctx.stroke(
            ellipsePath(rx: 0.45, ry: 0.45),
            with: .white,
            style: StrokeStyle(lineWidth: CGFloat(lineWidth), lineCap: .round, lineJoin: .round)
        )
    }

    let renderPass = try RenderPass {
        GraphicsContext3DRenderPipeline(context: context, viewProjection: viewProjection, viewport: viewport)
    }

    let renderer = try OffscreenRenderer(size: renderSize)
    let rendering = try renderer.render(renderPass)

    let width = Int(renderSize.width)
    let height = Int(renderSize.height)
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    rendering.texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

    // Bucket every lit pixel by angle around the center and measure how thick
    // the ring is in each wedge.
    let binCount = 36
    let center = SIMD2<Float>(Float(width) / 2, Float(height) / 2)
    var innerRadius = [Float](repeating: .greatestFiniteMagnitude, count: binCount)
    var outerRadius = [Float](repeating: 0, count: binCount)
    for y in 0..<height {
        for x in 0..<width where bytes[(y * width + x) * 4 + 1] > 60 {
            let offset = SIMD2<Float>(Float(x) + 0.5, Float(y) + 0.5) - center
            var angle = atan2(offset.y, offset.x)
            if angle < 0 {
                angle += 2 * .pi
            }
            let bin = min(binCount - 1, Int(angle / (2 * .pi) * Float(binCount)))
            innerRadius[bin] = min(innerRadius[bin], length(offset))
            outerRadius[bin] = max(outerRadius[bin], length(offset))
        }
    }

    for bin in 0..<binCount {
        let thickness = outerRadius[bin] - innerRadius[bin]
        // ±0.75px covers pixel quantization of a hard-edged 6px band.
        #expect(
            abs(thickness - lineWidth) < 0.75,
            "ring thickness \(thickness)px at \(bin * 360 / binCount) degrees, expected \(lineWidth)px"
        )
    }
}

@Test(.requiresMetal4)
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

// Read a single BGRA pixel out of a rendering, returned as RGBA.
@Test(.requiresMetal4)
@MainActor
func testGraphicsContext3D_textLabelsAtWorldPositions() throws {
    let projection = perspectiveProjection()
    let camera = float4x4(translation: SIMD3<Float>(0, 0, 4))
    let viewProjection = projection * camera.inverse
    let viewport = SIMD2<Float>(Float(defaultRenderSize.width), Float(defaultRenderSize.height))

    let context = GraphicsContext3D { ctx in
        ctx.fill(
            Path3D { path in
                path.move(to: [-0.9, -0.2, 0])
                path.addLine(to: [0.9, -0.2, 0])
                path.addLine(to: [0.9, 0.2, 0])
                path.addLine(to: [-0.9, 0.2, 0])
                path.closeSubpath()
            },
            with: .blue
        )
        // Labels keep a constant pixel size and draw over the filled quad.
        ctx.text("Hi", at: [0, 0, 0], with: .white, fontSize: 48)
        ctx.text("left", at: [-0.8, 0.8, 0], with: .yellow, fontSize: 32)
        // Behind the camera: must not draw anything.
        ctx.text("behind", at: [0, 0, 10], with: .red, fontSize: 32)
    }

    let renderPass = try RenderPass {
        GraphicsContext3DRenderPipeline(context: context, viewProjection: viewProjection, viewport: viewport)
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "GraphicsContext3DText"))
}

private func readPixel(_ rendering: OffscreenRenderer.Rendering, x: Int, y: Int) -> SIMD4<UInt8> {
    var bgra = [UInt8](repeating: 0, count: 4)
    rendering.texture.getBytes(
        &bgra,
        bytesPerRow: 4,
        from: MTLRegionMake2D(x, y, 1, 1),
        mipmapLevel: 0
    )
    return [bgra[2], bgra[1], bgra[0], bgra[3]]
}

@Test(.requiresMetal4)
@MainActor
func testGraphicsContext3D_fillRespectsAlpha() throws {
    // Regression test for issue #4: without blending enabled on the fill
    // pipeline a half-transparent white fill is written straight to the
    // framebuffer as opaque white.
    let projection = perspectiveProjection()
    let camera = float4x4(translation: SIMD3<Float>(0, 0, 3))
    let viewProjection = projection * camera.inverse
    let viewport = SIMD2<Float>(Float(defaultRenderSize.width), Float(defaultRenderSize.height))

    let quad = Path3D { path in
        path.move(to: [-0.6, -0.6, 0])
        path.addLine(to: [0.6, -0.6, 0])
        path.addLine(to: [0.6, 0.6, 0])
        path.addLine(to: [-0.6, 0.6, 0])
        path.closeSubpath()
    }

    let context = GraphicsContext3D { ctx in
        ctx.fill(quad, with: .white.opacity(0.5))
    }

    let renderPass = try RenderPass {
        GraphicsContext3DRenderPipeline(context: context, viewProjection: viewProjection, viewport: viewport)
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    let center = readPixel(rendering, x: Int(defaultRenderSize.width) / 2, y: Int(defaultRenderSize.height) / 2)

    // Half-alpha white over the opaque black clear color. The render target is
    // sRGB and Metal blends in linear space, so 0.5 linear encodes to ~188.
    #expect(center.x > 150 && center.x < 210)
    #expect(center.x == center.y && center.y == center.z)
}

@Test(.requiresMetal4)
@MainActor
func testGraphicsContext3D_strokeCrossingBehindCameraIsClipped() throws {
    // Regression test for issue #67: a segment that passes behind the camera used to be
    // mirrored across the screen. Every point here has x >= 0 and y >= 0, so its visible
    // part projects only into the top-right quadrant; a mirrored part lands bottom-left.
    let projection = perspectiveProjection()
    let camera = float4x4(translation: SIMD3<Float>(0, 0, 3))
    let viewProjection = projection * camera.inverse
    let viewport = SIMD2<Float>(Float(defaultRenderSize.width), Float(defaultRenderSize.height))

    let path = Path3D { path in
        path.move(to: [0.1, 0.1, 0])
        path.addLine(to: [0.5, 0.5, 10])
    }
    let context = GraphicsContext3D { ctx in
        ctx.stroke(path, with: .white, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
    }

    let renderPass = try RenderPass {
        GraphicsContext3DRenderPipeline(context: context, viewProjection: viewProjection, viewport: viewport)
    }
    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)

    let width = Int(defaultRenderSize.width)
    let height = Int(defaultRenderSize.height)
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    rendering.texture.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

    // Texture rows run top to bottom, so the bottom-left quadrant is the lower-left of the array.
    var litBottomLeft = 0
    var litTopRight = 0
    for y in 0..<height {
        for x in 0..<width where pixels[(y * width + x) * 4 + 1] > 0 {
            if x < width / 2 - 8, y > height / 2 + 8 {
                litBottomLeft += 1
            }
            if x > width / 2, y < height / 2 {
                litTopRight += 1
            }
        }
    }
    #expect(litTopRight > 0)
    #expect(litBottomLeft == 0)
}
