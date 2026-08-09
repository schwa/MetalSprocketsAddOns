import CoreGraphics
import GeometryLite3D
import Metal
import MetalKit
import MetalSprockets
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import simd

public struct FlatShader <Content>: Element where Content: Element {
    var modelViewProjection: float4x4
    var textureSpecifier: ColorSource
    var content: Content
    var useVertexColors: Bool

    @MSState
    var vertexShader: VertexShader

    @MSState
    var fragmentShader: FragmentShader

    // TODO: Remove texture specifier and use a parameter/element extension [FILE ME]
    public init(
        modelViewProjection: float4x4,
        textureSpecifier: ColorSource,
        useVertexColors: Bool = false,
        @ElementBuilder content: () throws -> Content
    ) throws {
        self.modelViewProjection = modelViewProjection
        self.textureSpecifier = textureSpecifier
        self.useVertexColors = useVertexColors
        self.content = try content()

        let shaderLibrary = ShaderLibrary.module.namespaced("FlatShader")

        // Setup function constants
        var constants = FunctionConstants()
        constants["USE_VERTEX_COLORS"] = .bool(useVertexColors)

        // Load shaders with function constants
        self.vertexShader = try shaderLibrary.function(named: "vertex_main", type: VertexShader.self, constants: constants)
        self.fragmentShader = try shaderLibrary.function(named: "fragment_main", type: FragmentShader.self, constants: constants)
    }

    public init(
        transforms: Transforms,
        textureSpecifier: ColorSource,
        useVertexColors: Bool = false,
        @ElementBuilder content: () throws -> Content
    ) throws {
        try self.init(
            modelViewProjection: transforms.modelViewProjectionMatrix,
            textureSpecifier: textureSpecifier,
            useVertexColors: useVertexColors,
            content: content
        )
    }

    public var body: some Element {
        get throws {
            try RenderPipeline(label: "FlatShader", vertexShader: vertexShader, fragmentShader: fragmentShader) {
                try content
                    .parameter("modelViewProjection", value: modelViewProjection)
                    .argumentBuffer("specifier", value: textureSpecifier)
            }
        }
    }
}
