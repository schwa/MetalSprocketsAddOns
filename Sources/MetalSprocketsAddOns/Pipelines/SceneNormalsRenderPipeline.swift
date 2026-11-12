import Metal
import MetalSprockets
import simd

/// Draws meshes' world-space shading normals into the current render pass's first colour attachment, for
/// ``ShadowContext/normalTexture``.
///
/// Use a floating-point colour format (such as `.rgba16Float`) cleared to zero; pixels with no geometry keep a zero
/// normal and the shadow passes ignore them. Meshes need positions at attribute 0 and normals at attribute 1.
///
/// ```swift
/// try RenderPass {
///     try SceneNormalsRenderPipeline(viewProjection: viewProjection, modelMatrix: modelMatrix) {
///         Draw(mesh: mesh).vertexBuffers(of: mesh)
///     }
///     .vertexDescriptor(MTLVertexDescriptor(mesh.vertexDescriptor))
/// }
/// ```
public struct SceneNormalsRenderPipeline<Content>: Element where Content: Element {
    let viewProjection: float4x4
    let modelMatrix: float4x4
    let content: Content

    @MSState
    private var vertexShader = ShaderLibrary.module.namespaced("SceneNormals").requiredFunction(named: "vertex_main", type: VertexShader.self)

    @MSState
    private var fragmentShader = ShaderLibrary.module.namespaced("SceneNormals").requiredFunction(named: "fragment_main", type: FragmentShader.self)

    public init(viewProjection: float4x4, modelMatrix: float4x4, @ElementBuilder content: () throws -> Content) rethrows {
        self.viewProjection = viewProjection
        self.modelMatrix = modelMatrix
        self.content = try content()
    }

    public var body: some Element {
        get throws {
            let upper = float3x3(
                SIMD3(modelMatrix.columns.0.x, modelMatrix.columns.0.y, modelMatrix.columns.0.z),
                SIMD3(modelMatrix.columns.1.x, modelMatrix.columns.1.y, modelMatrix.columns.1.z),
                SIMD3(modelMatrix.columns.2.x, modelMatrix.columns.2.y, modelMatrix.columns.2.z)
            )
            return try RenderPipeline(label: "Scene Normals", vertexShader: vertexShader, fragmentShader: fragmentShader) {
                content
                    .parameter("modelViewProjectionMatrix", value: viewProjection * modelMatrix)
                    .parameter("normalMatrix", value: upper.inverse.transpose)
            }
        }
    }
}
