import Metal
import MetalKit
import MetalSprockets
import MetalSprocketsAddOnsShaders

public struct WireframeRenderPipeline: Element {
    @MSState
    private var vertexShader = ShaderLibrary.module.namespaced("WireframeShader").requiredFunction(named: "vertex_main", type: VertexShader.self)

    @MSState
    private var fragmentShader = ShaderLibrary.module.namespaced("WireframeShader").requiredFunction(named: "fragment_main", type: FragmentShader.self)

    var mvpMatrix: float4x4
    var wireframeColor: SIMD4<Float>
    var mesh: MTKMesh

    public init(mvpMatrix: float4x4, wireframeColor: SIMD4<Float>, mesh: MTKMesh) {
        self.mvpMatrix = mvpMatrix
        self.wireframeColor = wireframeColor
        self.mesh = mesh
    }

    public var body: some Element {
        get throws {
            try RenderPipeline(vertexShader: vertexShader, fragmentShader: fragmentShader) {
                let uniforms = WireframeUniforms(modelViewProjectionMatrix: mvpMatrix, wireframeColor: wireframeColor)
                Draw { encoder in
                    encoder.setTriangleFillMode(.lines)
                    encoder.setVertexBuffers(of: mesh)
                    encoder.draw(mesh)
                }
                .parameter("uniforms", functionType: .vertex, value: uniforms)
                .parameter("uniforms", functionType: .fragment, value: uniforms)
            }
            .vertexDescriptor(mesh.vertexDescriptor)
        }
    }
}
