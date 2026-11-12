import Foundation
import MetalSprockets
import MetalSprocketsAddOnsShaders

public struct DebugRenderPipeline<Content>: Element where Content: Element {
    public let modelMatrix: float4x4
    public let normalMatrix: float3x3
    public let debugMode: DebugShadersMode
    public let lightPosition: float3
    public let cameraPosition: float3
    public let views: StereoViews
    public var viewProjectionMatrix: float4x4 { views.viewProjections[0] }

    let content: Content

    @MSState
    var vertexShader: VertexShader

    @MSState
    var fragmentShader: FragmentShader

    public init(modelMatrix: float4x4, normalMatrix: float3x3, debugMode: DebugShadersMode, lightPosition: float3, cameraPosition: float3, viewProjectionMatrix: float4x4, @ElementBuilder content: () throws -> Content) throws {
        try self.init(modelMatrix: modelMatrix, normalMatrix: normalMatrix, debugMode: debugMode, lightPosition: lightPosition, cameraPosition: cameraPosition, views: StereoViews(viewProjection: viewProjectionMatrix), content: content)
    }

    /// Draws into every view at once. With two views, each `Draw` in `content` must call `views.configure(encoder)`.
    public init(modelMatrix: float4x4, normalMatrix: float3x3, debugMode: DebugShadersMode, lightPosition: float3, cameraPosition: float3, views: StereoViews, @ElementBuilder content: () throws -> Content) throws {
        self.modelMatrix = modelMatrix
        self.normalMatrix = normalMatrix
        self.debugMode = debugMode
        self.lightPosition = lightPosition
        self.cameraPosition = cameraPosition
        self.views = views

        self.content = try content()

        let shaderLibrary = ShaderLibrary.module.namespaced("DebugShader")
        self.vertexShader = try shaderLibrary.vertex_main
        self.fragmentShader = try shaderLibrary.fragment_main
    }

    public var body: some Element {
        get throws {
            let debugShadersUniforms = DebugShadersUniforms(
                modelMatrix: modelMatrix,
                normalMatrix: normalMatrix,
                debugMode: debugMode.rawValue,
                lightPosition: lightPosition,
                cameraPosition: cameraPosition
            )
            let debugShadersAmplifiedUniforms = views.viewProjections.map { DebugShadersAmplifiedUniforms(viewProjectionMatrix: $0) }
            return try RenderPipeline(label: "DebugRenderPipeline", vertexShader: vertexShader, fragmentShader: fragmentShader) {
                content
                    .parameter("uniforms", functionType: .vertex, value: debugShadersUniforms)
                    .parameter("uniforms", functionType: .fragment, value: debugShadersUniforms)
                    .parameter("amplifiedUniforms", values: debugShadersAmplifiedUniforms)
            }
            .renderPipelineDescriptorTransformer { [count = views.count] descriptor in
                descriptor.maxVertexAmplificationCount = count
            }
        }
    }
}
