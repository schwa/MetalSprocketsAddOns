// Direct unit tests for GraphicsContext3D's command recording.

import CoreGraphics
@testable import MetalSprocketsAddOns
import simd
import SwiftUI
import Testing

@Test
@MainActor
func testGraphicsContext3D_emptyInit_hasNoCommands() {
    let ctx = GraphicsContext3D()
    #expect(ctx.commands.isEmpty)
}

@Test
@MainActor
func testGraphicsContext3D_builderInit_recordsCommands() {
    let ctx = GraphicsContext3D { ctx in
        ctx.stroke(Path3D { $0.move(to: [0, 0, 0]) }, with: .red, lineWidth: 1)
        ctx.fill(Path3D { $0.move(to: [1, 0, 0]) }, with: .blue)
    }
    #expect(ctx.commands.count == 2)
}

@Test
@MainActor
func testGraphicsContext3D_strokeWithStyle_recordsStroke() {
    var ctx = GraphicsContext3D()
    let style = StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
    ctx.stroke(Path3D { $0.move(to: [0, 0, 0]) }, with: .green, style: style)

    if case let .stroke(_, color, recordedStyle) = ctx.commands[0] {
        #expect(recordedStyle == style)
        // Green dominates the color even after sRGB conversion.
        #expect(color.y > color.x)
        #expect(color.y > color.z)
    } else {
        Issue.record("expected .stroke command")
    }
}

@Test
@MainActor
func testGraphicsContext3D_strokeWithLineWidth_recordsStrokeWithButtCap() {
    var ctx = GraphicsContext3D()
    ctx.stroke(Path3D { $0.move(to: [0, 0, 0]) }, with: .white, lineWidth: 2.5)

    if case let .stroke(_, _, style) = ctx.commands[0] {
        #expect(style.lineWidth == 2.5)
        #expect(style.lineCap == .butt)
    } else {
        Issue.record("expected .stroke command")
    }
}

@Test
@MainActor
func testGraphicsContext3D_equality() {
    let a = GraphicsContext3D { ctx in
        ctx.fill(Path3D { $0.move(to: [0, 0, 0]) }, with: .red)
    }
    let b = GraphicsContext3D { ctx in
        ctx.fill(Path3D { $0.move(to: [0, 0, 0]) }, with: .red)
    }
    let c = GraphicsContext3D()
    #expect(a == b)
    #expect(a != c)
}

// MARK: - Fill triangulation plane selection (issue #5)

private func quad(on plane: (Float, Float) -> SIMD3<Float>) -> Path3D {
    Path3D { p in
        p.move(to: plane(-1, -1))
        p.addLine(to: plane(1, -1))
        p.addLine(to: plane(1, 1))
        p.addLine(to: plane(-1, 1))
        p.closeSubpath()
    }
}

@Test
func testGeometryGenerator_polygonNormal_matchesPlane() {
    let xy: [SIMD3<Float>] = [[-1, -1, 0], [1, -1, 0], [1, 1, 0], [-1, 1, 0]]
    let xz: [SIMD3<Float>] = [[-1, 0, -1], [1, 0, -1], [1, 0, 1], [-1, 0, 1]]
    let yz: [SIMD3<Float>] = [[0, -1, -1], [0, 1, -1], [0, 1, 1], [0, -1, 1]]

    #expect(abs(normalize(GeometryGenerator.polygonNormal(xy)).z) == 1)
    #expect(abs(normalize(GeometryGenerator.polygonNormal(xz)).y) == 1)
    #expect(abs(normalize(GeometryGenerator.polygonNormal(yz)).x) == 1)

    // Collinear points have no plane.
    #expect(GeometryGenerator.polygonNormal([[0, 0, 0], [1, 1, 1], [2, 2, 2]]) == .zero)
}

@Test
func testGeometryGenerator_projectToDominantPlane_dropsPerpendicularAxis() {
    // A polygon on the XZ plane must not flatten to a line.
    let xz: [SIMD3<Float>] = [[-1, 0, -1], [1, 0, -1], [1, 0, 1], [-1, 0, 1]]
    let projected = GeometryGenerator.projectToDominantPlane(xz)
    let spreadX = projected.map(\.x).max()! - projected.map(\.x).min()!
    let spreadY = projected.map(\.y).max()! - projected.map(\.y).min()!
    #expect(spreadX > 0)
    #expect(spreadY > 0)
}

@Test
func testGeometryGenerator_fillGeometry_worksOnEveryAxisAlignedPlane() {
    let generator = GeometryGenerator(viewProjection: matrix_identity_float4x4, viewport: [256, 256])
    let color = SIMD4<Float>(1, 0, 0, 1)

    let planes: [(String, (Float, Float) -> SIMD3<Float>)] = [
        ("XY", { [$0 * 0.5, $1 * 0.5, 0] }),
        ("XZ", { [$0 * 0.5, 0, $1 * 0.5] }),
        ("YZ", { [0, $0 * 0.5, $1 * 0.5] })
    ]

    for (name, plane) in planes {
        let vertices = generator.generateFillGeometry(path: quad(on: plane), color: color)
        // A quad triangulates into two triangles.
        #expect(vertices.count == 6, "\(name) plane quad produced \(vertices.count) vertices")
    }
}
