import Metal
import MetalSprockets
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import MetalSupport

public struct BlinnPhongShader<Content>: Element where Content: Element {
    var vertexShader: VertexShader
    var fragmentShader: FragmentShader
    var label: String
    var viewCount: Int

    var content: Content

    /// Creates a Blinn-Phong shader pipeline.
    ///
    /// With `instanced`, bind per-instance matrices with `blinnPhongInstancedMatrices` and draw with an instance count.
    /// With `perInstanceMaterials` too, bind one material per instance with `blinnPhongMaterials`.
    ///
    /// With `viewCount` 2 (stereo, non-instanced only), bind matrices with `blinnPhongMatrices(modelMatrix:cameraMatrix:views:)`
    /// and call `views.configure(encoder)` in each `Draw`.
    public init(instanced: Bool = false, perInstanceMaterials: Bool = false, viewCount: Int = 1, @ElementBuilder content: () throws -> Content) throws {
        precondition(!instanced || viewCount == 1, "The instanced path draws one view")
        self.viewCount = viewCount
        let device = _MTLCreateSystemDefaultDevice()
        assert(device.argumentBuffersSupport == .tier2)
        let shaderLibrary = ShaderLibrary.module.namespaced("BlinnPhong")
        if instanced {
            var constants = FunctionConstants()
            constants["PER_INSTANCE_MATERIALS"] = .bool(perInstanceMaterials)
            vertexShader = try shaderLibrary.function(named: "vertex_instanced", type: VertexShader.self, constants: constants)
        } else {
            vertexShader = try shaderLibrary.vertex_main
        }
        fragmentShader = try shaderLibrary.fragment_main
        label = instanced ? "BlinnPhong Instanced" : "BlinnPhong"

        self.content = try content()
    }

    public var body: some Element {
        get throws {
            try RenderPipeline(label: label, vertexShader: vertexShader, fragmentShader: fragmentShader) {
                content
            }
            .renderPipelineDescriptorTransformer { [viewCount] descriptor in
                descriptor.maxVertexAmplificationCount = viewCount
            }
        }
    }
}
