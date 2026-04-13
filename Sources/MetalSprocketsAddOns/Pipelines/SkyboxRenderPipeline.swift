import GeometryLite3D
import Metal
import MetalSprockets
import simd

public struct SkyboxRenderPipeline: Element {
    let projectionMatrix: simd_float4x4
    let cameraMatrix: simd_float4x4
    let rotation: simd_quatf
    let texture: MTLTexture

    @MSState
    var vertexShader: VertexShader

    @MSState
    var fragmentShader: FragmentShader

    public init(projectionMatrix: simd_float4x4, cameraMatrix: simd_float4x4, rotation: simd_quatf = .init(ix: 0, iy: 0, iz: 0, r: 1), texture: MTLTexture) throws {
        self.projectionMatrix = projectionMatrix
        self.cameraMatrix = cameraMatrix
        self.rotation = rotation
        self.texture = texture
        let shaderLibrary = ShaderLibrary.module.namespaced("SkyboxShader")
        vertexShader = try shaderLibrary.vertex_main
        fragmentShader = try shaderLibrary.fragment_main
    }

    public var body: some Element {
        get throws {
            try RenderPipeline(vertexShader: vertexShader, fragmentShader: fragmentShader) {
                let positions: [Packed3<Float>] = [
                    // Front face (z = -1)
                    [1, -1, -1], [-1, -1, -1], [-1, 1, -1],
                    [1, -1, -1], [-1, 1, -1], [1, 1, -1],
                    // Back face (z = 1)
                    [1, -1, 1], [-1, 1, 1], [-1, -1, 1],
                    [1, -1, 1], [1, 1, 1], [-1, 1, 1],
                    // Bottom face (y = -1)
                    [1, -1, -1], [1, -1, 1], [-1, -1, 1],
                    [1, -1, -1], [-1, -1, 1], [-1, -1, -1],
                    // Top face (y = 1)
                    [1, 1, -1], [-1, 1, -1], [-1, 1, 1],
                    [1, 1, -1], [-1, 1, 1], [1, 1, 1],
                    // Left face (x = -1)
                    [-1, -1, -1], [-1, -1, 1], [-1, 1, 1],
                    [-1, -1, -1], [-1, 1, 1], [-1, 1, -1],
                    // Right face (x = 1)
                    [1, -1, -1], [1, 1, -1], [1, 1, 1],
                    [1, -1, -1], [1, 1, 1], [1, -1, 1]
                ]
                .map { $0 * 50 }
                Draw { encoder in
                    encoder.setVertexUnsafeBytes(of: positions, index: 0)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: positions.count)
                }
                .parameter("modelViewProjectionMatrix", functionType: .vertex, value: projectionMatrix * cameraMatrix.inverse * float4x4(rotation))
                .parameter("texture", texture: texture)
            }
            .vertexDescriptor(try vertexShader.inferredVertexDescriptor())
        }
    }
}
