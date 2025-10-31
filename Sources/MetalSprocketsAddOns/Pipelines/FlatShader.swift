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

        let shaderBundle = Bundle.metalSprocketsAddOnsShaders().orFatalError("Failed to load metal-sprockets example shaders bundle")
        let shaderLibrary = try ShaderLibrary(bundle: shaderBundle, namespace: "FlatShader")

        // Setup function constants
        var constants = FunctionConstants()
        constants["USE_VERTEX_COLORS"] = .bool(useVertexColors)

        // Load shaders with function constants
        self.vertexShader = try shaderLibrary.function(named: "vertex_main", type: VertexShader.self, constants: constants)
        self.fragmentShader = try shaderLibrary.function(named: "fragment_main", type: FragmentShader.self, constants: constants)
    }

    public var body: some Element {
        get throws {
            let textureSpecifierArgumentBuffer = textureSpecifier.toArgumentBuffer()

            try RenderPipeline(vertexShader: vertexShader, fragmentShader: fragmentShader) {
                content
                    .parameter("modelViewProjection", value: modelViewProjection)
                    .parameter("specifier", value: textureSpecifierArgumentBuffer)
                    .useResource(textureSpecifier.texture2D, usage: .read, stages: .fragment)
                    .useResource(textureSpecifier.textureCube, usage: .read, stages: .fragment)
                    .useResource(textureSpecifier.depth2D, usage: .read, stages: .fragment)
            }
        }
    }
}
