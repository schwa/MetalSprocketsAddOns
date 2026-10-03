import Metal
import MetalSprockets
import simd

/// Renders an equirectangular (lat-long) panorama as a skybox using a fullscreen
/// triangle and per-pixel direction-to-UV conversion.
///
/// Use this for sky/star maps distributed as 2D equirectangular panoramas
/// (e.g. the Tycho skymap, Poly Haven HDRIs). For cubemap textures use
/// ``SkyboxRenderPipeline`` instead.
public struct EquirectangularSkyboxRenderPipeline: Element {
    let projectionMatrix: simd_float4x4
    let cameraMatrix: simd_float4x4
    let rotation: simd_quatf
    let texture: MTLTexture
    let brightness: Float

    @MSState
    var vertexShader: VertexShader

    @MSState
    var fragmentShader: FragmentShader

    public init(projectionMatrix: simd_float4x4, cameraMatrix: simd_float4x4, rotation: simd_quatf = .init(ix: 0, iy: 0, iz: 0, r: 1), texture: MTLTexture, brightness: Float = 1.0) throws {
        self.projectionMatrix = projectionMatrix
        self.cameraMatrix = cameraMatrix
        self.rotation = rotation
        self.texture = texture
        self.brightness = brightness
        let shaderLibrary = ShaderLibrary.module.namespaced("EquirectangularSkyboxShader")
        vertexShader = try shaderLibrary.vertex_main
        fragmentShader = try shaderLibrary.fragment_main
    }

    /// Creates an equirectangular skybox pipeline from shared camera transforms.
    public init(viewTransforms: ViewTransforms, rotation: simd_quatf = .init(ix: 0, iy: 0, iz: 0, r: 1), texture: MTLTexture, brightness: Float = 1.0) throws {
        try self.init(projectionMatrix: viewTransforms.projectionMatrix, cameraMatrix: viewTransforms.cameraMatrix, rotation: rotation, texture: texture, brightness: brightness)
    }

    private var inverseViewProjectionMatrix: simd_float4x4 {
        var viewMatrix = cameraMatrix.inverse
        viewMatrix.columns.3 = [0, 0, 0, 1]
        return (projectionMatrix * viewMatrix * float4x4(rotation)).inverse
    }

    public var body: some Element {
        get throws {
            let inverseVP = inverseViewProjectionMatrix

            try RenderPipeline(label: "EquirectangularSkybox", vertexShader: vertexShader, fragmentShader: fragmentShader) {
                Draw { encoder in
                    encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
                }
                .parameter("texture", functionType: .fragment, texture: texture)
                .parameter("inverseViewProjectionMatrix", functionType: .vertex, value: inverseVP)
                .parameter("inverseViewProjectionMatrix", functionType: .fragment, value: inverseVP)
                .parameter("brightness", functionType: .fragment, value: brightness)
            }
        }
    }
}
