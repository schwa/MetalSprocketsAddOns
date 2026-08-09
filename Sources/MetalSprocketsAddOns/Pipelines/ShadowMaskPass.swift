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
    let outputTexture: MTLTexture
    let shadowMap: ShadowMap
    let inverseViewProjection: float4x4
    let shadowIntensity: Float

    @MSState
    var computeKernel: ComputeKernel

    /// Creates a shadow mask compute pass.
    ///
    /// - Parameters:
    ///   - sceneDepthTexture: The depth texture from the main scene render.
    ///   - outputTexture: The colour texture to darken in place.
    ///   - shadowMap: The shadow map rendered by ``ShadowMapDepthPass``.
    ///   - inverseViewProjection: Inverse of the camera's view-projection matrix.
    ///   - shadowIntensity: Shadow darkness (0–1, default 1).
    ///   - debug: When true, tints shadowed areas magenta instead of darkening them.
    public init(
        sceneDepthTexture: MTLTexture,
        outputTexture: MTLTexture,
        shadowMap: ShadowMap,
        inverseViewProjection: float4x4,
        shadowIntensity: Float = 1.0,
        debug: Bool = false
    ) throws {
        self.sceneDepthTexture = sceneDepthTexture
        self.outputTexture = outputTexture
        self.shadowMap = shadowMap
        self.inverseViewProjection = inverseViewProjection
        self.shadowIntensity = shadowIntensity

        let shaderLibrary = ShaderLibrary.module.namespaced("ShadowMask")
        var constants = FunctionConstants()
        constants["DEBUG"] = .bool(debug)
        computeKernel = try shaderLibrary.function(named: "shadow_mask_compute", type: ComputeKernel.self, constants: constants)
    }

    /// Creates a shadow mask compute pass from shared camera transforms.
    public init(
        sceneDepthTexture: MTLTexture,
        outputTexture: MTLTexture,
        shadowMap: ShadowMap,
        viewTransforms: ViewTransforms,
        shadowIntensity: Float = 1.0,
        debug: Bool = false
    ) throws {
        try self.init(
            sceneDepthTexture: sceneDepthTexture,
            outputTexture: outputTexture,
            shadowMap: shadowMap,
            inverseViewProjection: viewTransforms.inverseViewProjectionMatrix,
            shadowIntensity: shadowIntensity,
            debug: debug
        )
    }

    public var body: some Element {
        get throws {
            var maskParams = ShadowMaskParameters(
                inverseViewProjection: inverseViewProjection,
                shadowIntensity: shadowIntensity
            )
            var shadowParams = shadowMap.toParameters()
            let width = outputTexture.width
            let height = outputTexture.height

            try ComputePass(label: "ShadowMask") {
                try ComputePipeline(label: "ShadowMask", computeKernel: computeKernel) {
                    try ComputeDispatch(
                        threadsPerGrid: MTLSize(width: width, height: height, depth: 1),
                        threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
                    )
                }
                .onWorkloadEnter { environmentValues in
                    guard let encoder = environmentValues.computeCommandEncoder
                    else { return }
                    encoder.setTexture(sceneDepthTexture, index: 0)
                    encoder.setTexture(shadowMap.depthTexture, index: 1)
                    encoder.setTexture(outputTexture, index: 2)
                    encoder.setSamplerState(shadowMap.sampler, index: 0)
                    encoder.setBytes(&maskParams, length: MemoryLayout<ShadowMaskParameters>.stride, index: 0)
                    encoder.setBytes(&shadowParams, length: MemoryLayout<ShadowMapParameters>.stride, index: 1)
                }
            }
        }
    }
}
