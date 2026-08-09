import CoreGraphics
import simd
import SwiftUI

// GraphicsContext3D: A SwiftUI.Canvas-style API for rendering stroked and filled paths in 3D with pixel-perfect line widths.
// - GraphicsContext3D: Records stroke() and fill() commands with Path3D objects and styles
// - Path3D: Defines 3D paths using move/line/closeSubpath operations
// - GeometryGenerator: Transforms paths to screen space, generates triangulated geometry for line segments, round/square/butt caps, and miter/round/bevel joins
// - Line rendering uses screen-space geometry: 3D points → clip space → NDC → screen pixels (generate quads/caps/joins) → back to clip space
// - GraphicsContext3DRenderPipeline: Renders all generated geometry as a single triangle list with depth testing
// - Text labels are recorded with text(_:at:) and rendered with Slug at a constant pixel size on top of the geometry
// - StrokeStyle: Controls line width, cap style (.butt/.round/.square), join style (.miter/.round/.bevel), and miter limit

public struct GraphicsContext3D: Equatable {
    /// A text label anchored to a world-space position.
    ///
    /// Labels are drawn at a fixed pixel size, centred on the projected position, on top of
    /// everything else in the pass (they neither depth-test nor write depth).
    internal struct TextLabel: Equatable {
        var string: String
        var position: SIMD3<Float>
        var fontName: String
        var fontSize: CGFloat
        var color: SIMD4<Float>
    }

    internal enum DrawCommand: Equatable {
        case stroke(path: Path3D, color: SIMD4<Float>, style: StrokeStyle)
        case fill(path: Path3D, color: SIMD4<Float>)
        case text(TextLabel)
    }

    internal private(set) var commands: [DrawCommand] = []

    public init() {
        // Empty initializer
    }

    public init(_ builder: (inout Self) -> Void) {
        builder(&self)
    }

    public mutating func stroke(_ path: Path3D, with color: Color, style: StrokeStyle) {
        commands.append(.stroke(path: path, color: color.float4, style: style))
    }

    public mutating func stroke(_ path: Path3D, with color: Color, lineWidth: Float) {
        commands.append(.stroke(path: path, color: color.float4, style: StrokeStyle(lineWidth: CGFloat(lineWidth))))
    }

    public mutating func fill(_ path: Path3D, with color: Color) {
        commands.append(.fill(path: path, color: color.float4))
    }

    /// Draws a text label centred on a world-space position.
    ///
    /// The label is rendered with Slug at a fixed pixel size, so it keeps its size regardless
    /// of distance from the camera, and is drawn over the rest of the context's geometry.
    /// Labels whose position falls behind the camera are skipped.
    ///
    /// - Parameters:
    ///   - string: The text to draw. Multi-line strings are laid out as separate lines.
    ///   - position: World-space position the label is centred on.
    ///   - color: Text color.
    ///   - fontName: PostScript name of the font to rasterize with.
    ///   - fontSize: Font size in pixels.
    public mutating func text(_ string: String, at position: SIMD3<Float>, with color: Color = .white, fontName: String = "Helvetica", fontSize: CGFloat = 24) {
        commands.append(.text(TextLabel(string: string, position: position, fontName: fontName, fontSize: fontSize, color: color.float4)))
    }

    /// The text labels recorded in this context, in draw order.
    internal var textLabels: [TextLabel] {
        commands.compactMap { command in
            guard case let .text(label) = command else {
                return nil
            }
            return label
        }
    }
}
