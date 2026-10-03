import Metal
import MetalSprockets
import MetalSprocketsAddOnsShaders
import simd

public struct AxisAlignedWireframeBoxesRenderPipeline: Element {
    @MSState
    private var vertexShader = ShaderLibrary.module.namespaced("Boxes").requiredFunction(named: "vertex_main", type: VertexShader.self)

    @MSState
    private var fragmentShader = ShaderLibrary.module.namespaced("Boxes").requiredFunction(named: "fragment_main", type: FragmentShader.self)

    let mvpMatrix: float4x4
    let boxes: [BoxInstance]
    let nudge: SIMD3<Float>

    public init(mvpMatrix: float4x4, boxes: [BoxInstance], nudge: SIMD3<Float> = .zero) {
        self.mvpMatrix = mvpMatrix
        self.boxes = boxes
        self.nudge = nudge
    }

    public var body: some Element {
        get throws {
            try RenderPipeline(label: "AxisAlignedWireframeBoxes", vertexShader: vertexShader, fragmentShader: fragmentShader) {
                Draw { encoder in
                    encoder.drawPrimitives(primitiveType: .line, vertexStart: 0, vertexCount: 24, instanceCount: boxes.count)
                }
                .parameter("uniforms", functionType: .vertex, value: BoxesUniforms(mvpMatrix: mvpMatrix, nudge: nudge))
                .parameter("instances", functionType: .vertex, values: boxes)
            }
            .vertexDescriptor(vertexShader.inferredVertexDescriptor())
        }
    }
}
