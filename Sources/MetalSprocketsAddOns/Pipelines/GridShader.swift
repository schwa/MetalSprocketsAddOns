import GeometryLite3D
import MetalSprockets
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import simd
import SwiftUI

// MARK: - Highlighted Line

extension GridShader {
    /// A single highlighted grid line drawn on top of the base grid.
    public struct HighlightedLine: Sendable {
        /// Which axis the line runs along.
        public enum Axis: Int32, Sendable {
            /// A vertical line at a specific X position.
            case x = 0
            /// A horizontal line at a specific Y position.
            case y = 1
        }

        /// The axis this line is drawn on.
        public var axis: Axis
        /// The grid-space position of the line.
        public var position: Float
        /// The line width (0…1, same semantics as grid `lineWidth`).
        public var width: Float
        /// The RGBA color of the line.
        public var color: SIMD4<Float>

        public init(axis: Axis, position: Float = 0, width: Float = 0.02, color: SIMD4<Float>) {
            self.axis = axis
            self.position = position
            self.width = width
            self.color = color
        }
    }

    /// Major grid subdivision. Every `interval` minor cells, a major line is drawn.
    public struct MajorDivision: Sendable {
        /// How many minor cells between each major line (e.g. 10).
        public var interval: Int
        /// Line width for major lines per axis (0…1).
        public var lineWidth: SIMD2<Float>
        /// RGBA color for major lines.
        public var color: SIMD4<Float>

        public init(interval: Int = 10, lineWidth: SIMD2<Float> = SIMD2<Float>(0.02, 0.02), color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)) {
            self.interval = interval
            self.lineWidth = lineWidth
            self.color = color
        }
    }
}

// MARK: - GridShader

public struct GridShader: Element {
    @MSState
    private var vertexShader = ShaderLibrary.module.namespaced("GridShader").requiredFunction(named: "vertex_main", type: VertexShader.self)

    @MSState
    private var fragmentShader = ShaderLibrary.module.namespaced("GridShader").requiredFunction(named: "fragment_main", type: FragmentShader.self)

    var projectionMatrix: simd_float4x4
    var cameraMatrix: simd_float4x4
    var lineWidth: SIMD2<Float>
    var gridColor: SIMD4<Float>
    var backgroundColor: SIMD4<Float>
    var gridScale: SIMD2<Float>
    var highlightedLines: [HighlightedLine]
    var majorDivision: MajorDivision?

    public init(
        projectionMatrix: simd_float4x4,
        cameraMatrix: simd_float4x4,
        lineWidth: SIMD2<Float> = SIMD2<Float>(0.01, 0.01),
        gridColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1),
        backgroundColor: SIMD4<Float> = SIMD4<Float>(0.1, 0.1, 0.1, 1),
        gridScale: SIMD2<Float> = SIMD2<Float>(1, 1),
        highlightedLines: [HighlightedLine] = [],
        majorDivision: MajorDivision? = nil
    ) {
        self.projectionMatrix = projectionMatrix
        self.cameraMatrix = cameraMatrix
        self.lineWidth = lineWidth
        self.gridColor = gridColor
        self.backgroundColor = backgroundColor
        self.gridScale = gridScale
        self.highlightedLines = highlightedLines
        self.majorDivision = majorDivision
    }

    public var body: some Element {
        get throws {
            try RenderPipeline(vertexShader: vertexShader, fragmentShader: fragmentShader) {
                let modelMatrix = float4x4(xRotation: .degrees(90))
                let modelViewProjectionMatrix = projectionMatrix * cameraMatrix.inverse * modelMatrix
                Draw { encoder in
                    let positions: [Packed3<Float>] = [
                        [-1, 1, 0], [-1, -1, 0], [1, 1, 0], [1, -1, 0]
                    ]
                    .map { $0 * 2_000 }
                    let textureCoordinates: [SIMD2<Float>] = [
                        [-1, 1], [-1, -1], [1, 1], [1, -1]
                    ]
                    .map { $0 * 2_000 }
                    encoder.setVertexUnsafeBytes(of: positions, index: 0)
                    encoder.setVertexUnsafeBytes(of: textureCoordinates, index: 1)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: positions.count)
                }
                .parameter("modelViewProjectionMatrix", value: modelViewProjectionMatrix)
                .parameter("gridColor", value: gridColor)
                .parameter("backgroundColor", value: backgroundColor)
                .parameter("gridScale", value: gridScale)
                .parameter("lineWidth", value: lineWidth)
                .parameter("highlightedLines", value: highlightedLinesBuffer)
                .parameter("majorDivision", value: majorDivisionBuffer)
            }
            .vertexDescriptor(try vertexShader.inferredVertexDescriptor())
        }
    }

    /// Pack highlighted lines into the C struct layout matching `GridHighlightedLines`.
    private var highlightedLinesBuffer: GridHighlightedLines {
        var buffer = GridHighlightedLines()
        buffer.count = Int32(min(highlightedLines.count, Int(GRID_MAX_HIGHLIGHTED_LINES)))
        let count = Int(buffer.count)
        withUnsafeMutablePointer(to: &buffer.lines) { tuplePtr in
            tuplePtr.withMemoryRebound(to: GridHighlightedLine.self, capacity: Int(GRID_MAX_HIGHLIGHTED_LINES)) { ptr in
                for i in 0..<count {
                    let hl = highlightedLines[i]
                    ptr[i].axis = hl.axis.rawValue
                    ptr[i].position = hl.position
                    ptr[i].width = hl.width
                    ptr[i]._padding = 0
                    ptr[i].color = hl.color
                }
            }
        }
        return buffer
    }

    private var majorDivisionBuffer: GridMajorDivision {
        if let majorDivision {
            var buffer = GridMajorDivision()
            buffer.interval = Int32(majorDivision.interval)
            buffer._padding0 = 0
            buffer.lineWidth = majorDivision.lineWidth
            buffer.color = majorDivision.color
            return buffer
        }
        // interval = 0 disables major division in the shader
        return GridMajorDivision()
    }
}
