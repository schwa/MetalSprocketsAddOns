import Metal
import MetalSprockets
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import simd

/// A screen-space post-process compute pass that reads the scene depth buffer and shadow map
/// and darkens shadowed pixels of an already-rendered colour texture in place.
///
/// - Important: This element runs its own compute pass, so it must be placed as a *sibling* of
/// the scene's render pass, not inside it. `outputTexture` needs `.shaderWrite` usage and
/// `sceneDepthTexture` needs `.shaderRead`.
///
/// Usage:
/// ```swift
/// Group {
///     RenderPass {
///         // ... render scene with lighting (no shadow awareness needed) ...
///     }
///     ShadowMaskPass(
///         sceneDepthTexture: sceneDepth,
///         outputTexture: colorTexture,
///         shadowMap: shadowMap,
///         inverseViewProjection: inverseVP
///     )
/// }
/// ```
public struct ShadowMaskPass: Element {
    let sceneDepthTexture: MTLTexture
    let sceneNormalTexture: MTLTexture?
    let outputTexture: MTLTexture
    let shadowMap: ShadowMap
    /// One per view. With more than one, the textures are arrays with one slice per view.
    let inverseViewProjections: [float4x4]
    let shadowIntensity: Float

    @MSState
    var computeKernel: ComputeKernel

    @MSEnvironment(\.submissionIndex)
    var submissionIndex

    /// Creates a shadow mask compute pass.
    ///
    /// - Parameters:
    ///   - sceneDepthTexture: The depth texture from the main scene render.
    ///   - outputTexture: The colour texture to darken in place.
    ///   - shadowMap: The shadow map rendered by ``ShadowMapDepthPass``.
    ///   - inverseViewProjection: Inverse of the camera's view-projection matrix.
    ///   - shadowIntensity: Shadow darkness (0–1, default 1).
    ///   - debug: When true, tints shadowed areas magenta instead of darkening them.
    ///   - sceneNormalTexture: Optional world-space shading normals (see ``ShadowContext/normalTexture``).
    public init(
        sceneDepthTexture: MTLTexture,
        outputTexture: MTLTexture,
        shadowMap: ShadowMap,
        inverseViewProjection: float4x4,
        shadowIntensity: Float = 1.0,
        debug: Bool = false,
        sceneNormalTexture: MTLTexture? = nil
    ) throws {
        self.sceneDepthTexture = sceneDepthTexture
        self.sceneNormalTexture = sceneNormalTexture
        self.outputTexture = outputTexture
        self.shadowMap = shadowMap
        self.inverseViewProjections = [inverseViewProjection]
        self.shadowIntensity = shadowIntensity
        computeKernel = try Self.kernel(layered: false, debug: debug, hasNormals: sceneNormalTexture != nil)
    }

    /// Creates a shadow mask pass for several views at once, such as both eyes of a visionOS immersive space.
    ///
    /// The scene was drawn into array textures with one slice per view (see ``ShadowContext/views``): slice `i` of
    /// `sceneDepthTexture`, `outputTexture` and `sceneNormalTexture` belongs to `views` view `i`.
    public init(
        sceneDepthTexture: MTLTexture,
        outputTexture: MTLTexture,
        shadowMap: ShadowMap,
        views: StereoViews,
        shadowIntensity: Float = 1.0,
        debug: Bool = false,
        sceneNormalTexture: MTLTexture? = nil
    ) throws {
        try ShadowContext.validateLayered(views: views, textures: [sceneDepthTexture, outputTexture] + (sceneNormalTexture.map { [$0] } ?? []))
        self.sceneDepthTexture = sceneDepthTexture
        self.sceneNormalTexture = sceneNormalTexture
        self.outputTexture = outputTexture
        self.shadowMap = shadowMap
        self.inverseViewProjections = views.viewProjections.map(\.inverse)
        self.shadowIntensity = shadowIntensity
        computeKernel = try Self.kernel(layered: true, debug: debug, hasNormals: sceneNormalTexture != nil)
    }

    private static func kernel(layered: Bool, debug: Bool, hasNormals: Bool) throws -> ComputeKernel {
        var constants = FunctionConstants()
        constants["DEBUG"] = .bool(debug)
        constants["HAS_NORMALS"] = .bool(hasNormals)
        let name = layered ? "shadow_mask_compute_layered" : "shadow_mask_compute"
        return try ShaderLibrary.module.namespaced("ShadowMask").function(named: name, type: ComputeKernel.self, constants: constants)
    }

    /// Creates a shadow mask compute pass from shared camera transforms.
    public init(
        sceneDepthTexture: MTLTexture,
        outputTexture: MTLTexture,
        shadowMap: ShadowMap,
        viewTransforms: ViewTransforms,
        shadowIntensity: Float = 1.0,
        debug: Bool = false,
        sceneNormalTexture: MTLTexture? = nil
    ) throws {
        try self.init(
            sceneDepthTexture: sceneDepthTexture,
            outputTexture: outputTexture,
            shadowMap: shadowMap,
            inverseViewProjection: viewTransforms.inverseViewProjectionMatrix,
            shadowIntensity: shadowIntensity,
            debug: debug,
            sceneNormalTexture: sceneNormalTexture
        )
    }

    public var body: some Element {
        get throws {
            let maskParams = ShadowMaskParameters(
                inverseViewProjection: inverseViewProjections[0],
                shadowIntensity: shadowIntensity
            )
            let shadowParams = shadowMap.toParameters()
            let width = outputTexture.width
            let height = outputTexture.height
            let layered = outputTexture.textureType == .type2DArray
            let inverseViewProjections = inverseViewProjections

            try ComputePass(label: "ShadowMask") {
                // Wait for the scene pass to finish writing depth and colour.
                QueueBarrier(after: [.fragment, .dispatch], before: .dispatch)
                try ComputePipeline(label: "ShadowMask", computeKernel: computeKernel) {
                    try ComputeDispatch(
                        threadsPerGrid: MTLSize(width: width, height: height, depth: layered ? inverseViewProjections.count : 1),
                        threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
                    )
                    .parameters { parameters in
                        if layered {
                            parameters.set("inverseViewProjections", values: inverseViewProjections)
                        }
                    }
                    .parameter("sceneDepth", texture: sceneDepthTexture)
                    .parameter("shadowMapTexture", texture: shadowMap.depthTexture(forSubmission: submissionIndex))
                    .parameter("outputTexture", texture: outputTexture)
                    .parameters { parameters in
                        if let sceneNormalTexture = self.sceneNormalTexture {
                            parameters.set("sceneNormals", texture: sceneNormalTexture)
                        }
                    }
                    .parameter("shadowMapSampler", samplerState: shadowMap.sampler)
                    .parameter("params", value: maskParams)
                    .parameter("shadowMapParams", value: shadowParams)
                }
            }
        }
    }
}
