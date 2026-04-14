import Metal
import MetalSprockets
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import simd

/// A fullscreen post-process pass that reads the scene depth buffer and shadow map
/// to produce a shadow overlay. Renders black with alpha = shadow darkness using
/// multiplicative blending, so it darkens shadowed areas of the previously rendered scene.
///
/// Usage:
/// ```swift
/// RenderPass {
///     // ... render scene with lighting (no shadow awareness needed) ...
///     ShadowMaskPass(
///         sceneDepthTexture: sceneDepth,
///         shadowMap: shadowMap,
///         inverseViewProjection: inverseVP
///     )
/// }
/// ```
public struct ShadowMaskPass: Element {
    let sceneDepthTexture: MTLTexture
    let shadowMap: ShadowMap
    let inverseViewProjection: float4x4
    let debug: Bool

    @MSState
    var vertexShader: VertexShader

    @MSState
    var fragmentShader: FragmentShader

    public init(sceneDepthTexture: MTLTexture, shadowMap: ShadowMap, inverseViewProjection: float4x4, debug: Bool = false) throws {
        self.sceneDepthTexture = sceneDepthTexture
        self.shadowMap = shadowMap
        self.inverseViewProjection = inverseViewProjection
        self.debug = debug

        let shaderLibrary = ShaderLibrary.module.namespaced("ShadowMask")
        vertexShader = try shaderLibrary.vertex_main
        var constants = FunctionConstants()
        constants["DEBUG"] = .bool(debug)
        fragmentShader = try shaderLibrary.function(named: "fragment_main", type: FragmentShader.self, constants: constants)
    }

    public var body: some Element {
        get throws {
            let params = shadowMap.toParameters()
            try RenderPipeline(label: "ShadowMask", vertexShader: vertexShader, fragmentShader: fragmentShader) {
                Draw { encoder in
                    encoder.setFragmentTexture(sceneDepthTexture, index: 0)
                    encoder.setFragmentTexture(shadowMap.depthTexture, index: 1)
                    encoder.setFragmentSamplerState(shadowMap.sampler, index: 0)
                    var invVP = inverseViewProjection
                    encoder.setFragmentBytes(&invVP, length: MemoryLayout<float4x4>.stride, index: 0)
                    var shadowParams = params
                    encoder.setFragmentBytes(&shadowParams, length: MemoryLayout<ShadowMapParameters>.stride, index: 1)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                }
            }
            .renderPipelineDescriptorModifier { descriptor in
                // Alpha blending: src * srcAlpha + dst * (1 - srcAlpha)
                // Normal mode: src is black, so dst * (1 - alpha) = darkening
                // Debug mode: src is magenta, blended over scene
                guard let attachment = descriptor.colorAttachments[0]
                else { return }
                attachment.isBlendingEnabled = true
                attachment.rgbBlendOperation = .add
                attachment.alphaBlendOperation = .add
                attachment.sourceRGBBlendFactor = .sourceAlpha
                attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                attachment.sourceAlphaBlendFactor = .zero
                attachment.destinationAlphaBlendFactor = .one
            }
            .depthCompare(function: .always, enabled: false)
        }
    }
}
