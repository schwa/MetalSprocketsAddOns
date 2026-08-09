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
func testGraphicsContext3D_text_recordsLabel() {
    var ctx = GraphicsContext3D()
    ctx.text("origin", at: [1, 2, 3], with: .red, fontName: "Helvetica-Bold", fontSize: 32)

    #expect(ctx.commands.count == 1)
    if case let .text(label) = ctx.commands[0] {
        #expect(label.string == "origin")
        #expect(label.position == SIMD3<Float>(1, 2, 3))
        #expect(label.fontName == "Helvetica-Bold")
        #expect(label.fontSize == 32)
        #expect(label.color.x > label.color.y)
    } else {
        Issue.record("expected .text command")
    }
}

@Test
@MainActor
func testGraphicsContext3D_textLabels_areReturnedInDrawOrder() {
    let ctx = GraphicsContext3D { ctx in
        ctx.text("first", at: .zero)
        ctx.fill(Path3D { $0.move(to: [0, 0, 0]) }, with: .blue)
        ctx.text("second", at: [0, 1, 0])
    }
    #expect(ctx.textLabels.map(\.string) == ["first", "second"])
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

// MARK: - Curve subdivision (issue #25)

// Orthographic-ish view projection that maps world [-1, 1] to NDC [-1, 1] so
// screen-space measurements are easy to reason about.
private let unitViewProjection = matrix_identity_float4x4
private let unitViewport = SIMD2<Float>(256, 256)

// Largest distance from `points` to the ellipse of radii (rx, ry), in world units.
private func maxEllipseDeviation(_ points: [SIMD3<Float>], rx: Float, ry: Float) -> Float {
    points.reduce(0) { worst, point in
        // Normalize onto the unit circle; scale back by the smaller radius to
        // turn the implicit-function error into an approximate distance.
        let normalized = SIMD2<Float>(point.x / rx, point.y / ry)
        return max(worst, abs(length(normalized) - 1) * min(rx, ry))
    }
}

@Test
func testGeometryGenerator_ellipsePathIsSmooth() {
    // The four-arc ellipse fixture must actually trace an ellipse. The old
    // fixture used the cubic k constant in quadratic curves, which bulged by
    // ~6% of the radius and left a visible corner at every quadrant.
    let rx: Float = 0.55
    let ry: Float = 0.4
    let generator = GeometryGenerator(viewProjection: unitViewProjection, viewport: unitViewport)
    let points = generator.extractPoints(from: ellipsePath(rx: rx, ry: ry))
    #expect(maxEllipseDeviation(points, rx: rx, ry: ry) < 0.002)
}

// Small radii are the worst case: the adaptive segment count bottoms out at its
// floor, so the arc between chords is only as fine as that floor allows.
@Test(arguments: [Float(0.05), 0.1, 0.12, 0.15, 0.25, 0.4])
func testGeometryGenerator_subdivisionIsSubPixel(radius: Float) {
    // A subdivided curve should never sag more than a fraction of a pixel away
    // from the true curve, otherwise fills and strokes look faceted.
    let generator = GeometryGenerator(viewProjection: unitViewProjection, viewport: unitViewport)
    let points = generator.extractPoints(from: ellipsePath(rx: radius, ry: radius))

    // Chord midpoints fall inside the circle by the sagitta; measure it in pixels.
    let pixelsPerUnit = unitViewport.x / 2
    var worstSagitta: Float = 0
    for i in points.indices {
        let midpoint = (points[i] + points[(i + 1) % points.count]) / 2
        worstSagitta = max(worstSagitta, (radius - length(SIMD2(midpoint.x, midpoint.y))) * pixelsPerUnit)
    }
    #expect(worstSagitta < 0.25, "worst sagitta \(worstSagitta)px over \(points.count) points")
}

@Test
func testGeometryGenerator_segmentCount_isBoundedAndAdaptive() {
    // Tiny curves still get a usable floor, huge curves stay bounded.
    #expect(GeometryGenerator.segmentCount(forScreenLength: 0) == 8)
    #expect(GeometryGenerator.segmentCount(forScreenLength: 200) == 50)
    #expect(GeometryGenerator.segmentCount(forScreenLength: 100_000) == 64)
}
