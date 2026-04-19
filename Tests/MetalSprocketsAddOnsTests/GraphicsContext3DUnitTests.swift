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
