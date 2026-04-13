import Metal
import MetalSprockets
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport

public struct BlinnPhongShader<Content>: Element where Content: Element {
    var vertexShader: VertexShader
    var fragmentShader: FragmentShader

    var content: Content

    /// Creates a Blinn-Phong shader pipeline.
    ///
    /// - Parameters:
    ///   - shadowMapEnabled: When `true`, the fragment shader expects shadow map
    ///     parameters, texture, and sampler to be bound via the `.shadowMap(_:)` modifier.
    ///   - shadowDebug: When `true`, visualizes shadow factor as magenta (shadowed) to green (lit).
    public init(shadowMapEnabled: Bool = false, shadowDebug: Bool = false, @ElementBuilder content: () throws -> Content) throws {
        let device = _MTLCreateSystemDefaultDevice()
        assert(device.argumentBuffersSupport == .tier2)
        let shaderLibrary = ShaderLibrary.module.namespaced("BlinnPhong")
        vertexShader = try shaderLibrary.vertex_main

        var constants = FunctionConstants()
        constants["SHADOW_MAP_ENABLED"] = .bool(shadowMapEnabled)
        constants["SHADOW_DEBUG"] = .bool(shadowDebug)
        fragmentShader = try shaderLibrary.function(named: "fragment_main", type: FragmentShader.self, constants: constants)

        self.content = try content()
    }

    public var body: some Element {
        get throws {
            try RenderPipeline(vertexShader: vertexShader, fragmentShader: fragmentShader) {
                content
            }
        }
    }
}
