import Metal
import MetalSprockets
import MetalSprocketsAddOnsShaders
import simd

public struct AxisLinesRenderPipeline: Element {
    public struct Axes: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let x = Self(rawValue: 1 << 0)
        public static let y = Self(rawValue: 1 << 1)
        public static let z = Self(rawValue: 1 << 2)
        public static let all: Self = [.x, .y, .z]
    }

    @MSState
    private var vertexShader = ShaderLibrary.module.namespaced("AxisLines").requiredFunction(named: "vertex_main", type: VertexShader.self)

    @MSState
    private var fragmentShader = ShaderLibrary.module.namespaced("AxisLines").requiredFunction(named: "fragment_main", type: FragmentShader.self)

    let mvpMatrix: float4x4
    let viewMatrix: float4x4
    let projectionMatrix: float4x4
    let viewportSize: SIMD2<Float>
    let lineWidth: Float
    let length: Float
    let nudge: SIMD3<Float>
    let xAxisColor: SIMD4<Float>
    let yAxisColor: SIMD4<Float>
    let zAxisColor: SIMD4<Float>
    let axes: Axes

    public init(
        mvpMatrix: float4x4,
        viewMatrix: float4x4,
        projectionMatrix: float4x4,
        viewportSize: SIMD2<Float>,
        lineWidth: Float = 2.0,
        length: Float = 2_000,
        nudge: SIMD3<Float> = .zero,
        xAxisColor: SIMD4<Float> = [1, 0, 0, 1],
        yAxisColor: SIMD4<Float> = [0, 1, 0, 1],
        zAxisColor: SIMD4<Float> = [0, 0, 1, 1],
        axes: Axes = .all
    ) throws {
        self.mvpMatrix = mvpMatrix
        self.viewMatrix = viewMatrix
        self.projectionMatrix = projectionMatrix
        self.viewportSize = viewportSize
        self.lineWidth = lineWidth
        self.length = length
        self.nudge = nudge
        self.xAxisColor = xAxisColor
        self.yAxisColor = yAxisColor
        self.zAxisColor = zAxisColor
        self.axes = axes
    }

    public var body: some Element {
        get throws {
            try RenderPipeline(label: "AxisLines", vertexShader: vertexShader, fragmentShader: fragmentShader) {
                let uniforms = AxisLinesUniforms(
                    mvpMatrix: mvpMatrix,
                    viewMatrix: viewMatrix,
                    projectionMatrix: projectionMatrix,
                    viewportSize: viewportSize,
                    lineWidth: lineWidth,
                    length: length,
                    nudge: nudge,
                    xAxisColor: xAxisColor,
                    yAxisColor: yAxisColor,
                    zAxisColor: zAxisColor
                )
                let axes = axes
                Draw { encoder in
                    // The shader derives the axis from vertex_id / 6, so each axis is a separate 6-vertex range.
                    for (index, axis) in [Axes.x, .y, .z].enumerated() where axes.contains(axis) {
                        encoder.drawPrimitives(primitiveType: .triangle, vertexStart: index * 6, vertexCount: 6)
                    }
                }
                .parameter("uniforms", functionType: .vertex, value: uniforms)
            }
            .vertexDescriptor(vertexShader.inferredVertexDescriptor())
        }
    }
}
