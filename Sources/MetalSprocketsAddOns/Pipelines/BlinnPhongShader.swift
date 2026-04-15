import Metal
import MetalSprockets
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import MetalSupport

public struct BlinnPhongShader<Content>: Element where Content: Element {
    var vertexShader: VertexShader
    var fragmentShader: FragmentShader

    var content: Content

    /// Creates a Blinn-Phong shader pipeline.
    public init(@ElementBuilder content: () throws -> Content) throws {
        let device = _MTLCreateSystemDefaultDevice()
        assert(device.argumentBuffersSupport == .tier2)
        let shaderLibrary = ShaderLibrary.module.namespaced("BlinnPhong")
        vertexShader = try shaderLibrary.vertex_main
        fragmentShader = try shaderLibrary.fragment_main

        self.content = try content()
    }

    public var body: some Element {
        get throws {
            try RenderPipeline(label: "BlinnPhong", vertexShader: vertexShader, fragmentShader: fragmentShader) {
                content
            }
        }
    }
}
