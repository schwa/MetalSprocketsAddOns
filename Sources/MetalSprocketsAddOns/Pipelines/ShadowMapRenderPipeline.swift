import Metal
import MetalKit
import MetalSprockets
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import MetalSupport
import ModelIO
import simd

// MARK: - ShadowMap

/// Manages shadow map array texture and light matrix computation for multiple shadow-casting lights.
public struct ShadowMap {
    /// The depth array texture — one slice per shadow-casting light.
    public let depthTexture: MTLTexture

    /// The sampler used for shadow map lookups (comparison sampler).
    public let sampler: MTLSamplerState

    /// Per-light view-projection matrices.
    public var lightViewProjectionMatrices: [simd_float4x4]

    /// Constant depth bias to prevent acne.
    public var depthBias: Float

    /// Slope-scale depth bias — scales with the surface slope relative to the light.
    public var slopeScale: Float

    /// The resolution of each shadow map (square).
    public let resolution: Int

    /// Maximum number of shadow-casting lights.
    public let lightCount: Int

    /// Whether to use inverse Z (reversed depth buffer) for better precision.
    public let useInverseZ: Bool

    /// Creates a new shadow map array with the given resolution and light count.
    ///
    /// - Parameters:
    ///   - resolution: Width and height of each shadow map slice (default 2048).
    ///   - lightCount: Number of shadow-casting lights (default 1).
    ///   - depthBias: Constant depth bias to prevent shadow acne.
    ///   - slopeScale: Slope-scale depth bias.
    ///   - useInverseZ: Use inverse Z (reversed depth) for better precision (default true).
    public init(resolution: Int = 2_048, lightCount: Int = 1, depthBias: Float = 2.0, slopeScale: Float = 2.0, useInverseZ: Bool = true) throws {
        self.resolution = resolution
        self.lightCount = lightCount
        self.depthBias = depthBias
        self.slopeScale = slopeScale
        self.useInverseZ = useInverseZ
        self.lightViewProjectionMatrices = Array(repeating: .identity, count: lightCount)

        let device = _MTLCreateSystemDefaultDevice()

        // Create depth array texture — one slice per light
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2DArray
        descriptor.pixelFormat = .depth32Float
        descriptor.width = resolution
        descriptor.height = resolution
        descriptor.arrayLength = lightCount
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        depthTexture = try device.makeTexture(descriptor: descriptor)
            .orThrow(.resourceCreationFailure("Failed to create shadow map depth array texture"))
        depthTexture.label = "Shadow Map Depth Array"

        // Create comparison sampler for PCF
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.compareFunction = Self.depthCompareFunction(useInverseZ: useInverseZ)
        samplerDescriptor.sAddressMode = .clampToBorderColor
        samplerDescriptor.tAddressMode = .clampToBorderColor
        samplerDescriptor.borderColor = Self.samplerBorderColor(useInverseZ: useInverseZ)
        samplerDescriptor.supportArgumentBuffers = true
        sampler = try device.makeSamplerState(descriptor: samplerDescriptor)
            .orThrow(.resourceCreationFailure("Failed to create shadow map sampler"))
    }

    /// Updates the view-projection matrix for a specific light.
    ///
    /// - Parameters:
    ///   - index: The light index (0-based).
    ///   - position: World-space position of the light.
    ///   - target: The point the light looks at.
    ///   - up: Up vector for the light's view (default [0,1,0]).
    ///   - orthoSize: Half-extent of the orthographic frustum.
    ///   - near: Near plane distance.
    ///   - far: Far plane distance.
    public mutating func updateDirectionalLight(
        at index: Int,
        position: SIMD3<Float>,
        target: SIMD3<Float> = .zero,
        up: SIMD3<Float> = [0, 1, 0],
        orthoSize: Float = 15,
        near: Float = 0.1,
        far: Float = 50
    ) {
        let lightView = float4x4.lookAt(eye: position, target: target, up: up)
        let lightProjection = float4x4.orthographic(
            left: -orthoSize,
            right: orthoSize,
            bottom: -orthoSize,
            top: orthoSize,
            near: near,
            far: far,
            inverseZ: useInverseZ
        )
        lightViewProjectionMatrices[index] = lightProjection * lightView
    }

    // MARK: Depth convention
    //
    // Every decision that depends on `useInverseZ` lives here so the depth pass, the sampler and
    // the tests all agree on one set of answers.

    static func depthCompareFunction(useInverseZ: Bool) -> MTLCompareFunction {
        useInverseZ ? .greaterEqual : .lessEqual
    }

    static func samplerBorderColor(useInverseZ: Bool) -> MTLSamplerBorderColor {
        useInverseZ ? .opaqueBlack : .opaqueWhite
    }

    /// Depth comparison used both by the depth pass's depth test and by the shadow sampler.
    var depthCompareFunction: MTLCompareFunction {
        Self.depthCompareFunction(useInverseZ: useInverseZ)
    }

    /// Border colour for shadow lookups outside the light's frustum — the "unshadowed" depth value.
    var samplerBorderColor: MTLSamplerBorderColor {
        Self.samplerBorderColor(useInverseZ: useInverseZ)
    }

    /// Depth value the shadow map is cleared to: the far plane for the depth convention in use.
    var clearDepth: Double {
        useInverseZ ? 0.0 : 1.0
    }

    /// ``depthBias`` with the sign the depth convention requires — inverse Z counts the other way,
    /// so the bias has to be negated to still push samples away from the light.
    var appliedDepthBias: Float {
        useInverseZ ? -depthBias : depthBias
    }

    /// ``slopeScale`` with the sign the depth convention requires. See ``appliedDepthBias``.
    var appliedSlopeScale: Float {
        useInverseZ ? -slopeScale : slopeScale
    }

    /// Points `descriptor` at the shadow map slice belonging to `lightIndex`.
    ///
    /// The depth pass renders one light per pass into a single array slice, so there is no colour
    /// attachment and the render target array length is 1.
    func configureRenderPassDescriptor(_ descriptor: MTL4RenderPassDescriptor, lightIndex: Int) {
        descriptor.colorAttachments[0].texture = nil
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .dontCare
        descriptor.depthAttachment.texture = depthTexture
        descriptor.depthAttachment.slice = lightIndex
        descriptor.depthAttachment.loadAction = .clear
        descriptor.depthAttachment.clearDepth = clearDepth
        descriptor.depthAttachment.storeAction = .store
        descriptor.renderTargetArrayLength = 1
    }

    /// Returns the `ShadowMapParameters` struct for passing to shaders.
    public func toParameters() -> ShadowMapParameters {
        var params = ShadowMapParameters()
        params.lightCount = Int32(lightCount)
        params.mapSize = Float(resolution)
        withUnsafeMutablePointer(to: &params.lights) { tuple in
            tuple.withMemoryRebound(to: ShadowLightParameters.self, capacity: Int(MAX_SHADOW_LIGHTS)) { lights in
                for i in 0..<min(lightCount, Int(MAX_SHADOW_LIGHTS)) {
                    lights[i] = ShadowLightParameters(lightViewProjectionMatrix: lightViewProjectionMatrices[i])
                }
            }
        }
        return params
    }
}

// MARK: - ShadowMapDepthPass

/// An Element that renders geometry into a shadow map depth texture from the light's POV.
///
/// - Important: This element emits its own `RenderPass` per shadow-casting light, so it must be
/// placed as a *sibling* of the scene's render pass, never inside one. Nesting it inside a
/// `RenderPass` opens a second command encoder on the same command buffer, which Metal rejects
/// with "A command encoder is already encoding to this command buffer".
///
/// Usage:
/// ```swift
/// Group {
///     ShadowMapDepthPass(shadowMap: shadowMap, vertexDescriptor: mesh.vertexDescriptor) {
///         // Draw calls for shadow casters — same geometry, just needs positions
///         Draw(mesh: mesh)
///             .vertexBuffers(of: mesh)
///         .parameter("modelMatrix", functionType: .vertex, value: modelMatrix)
///     }
///     RenderPass {
///         // ... scene ...
///     }
///     ShadowMaskPass(...)
/// }
/// ```
public struct ShadowMapDepthPass<Content>: Element where Content: Element {
    let shadowMap: ShadowMap
    let content: Content
    let vertexDescriptor: MTLVertexDescriptor

    @MSState
    var vertexShader: VertexShader

    @MSState
    var fragmentShader: FragmentShader

    public init(shadowMap: ShadowMap, vertexDescriptor: MDLVertexDescriptor, @ElementBuilder content: () throws -> Content) throws {
        self.shadowMap = shadowMap
        guard let metalDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor) else {
            fatalError("Failed to convert MDLVertexDescriptor to MTLVertexDescriptor")
        }
        self.vertexDescriptor = metalDescriptor

        self.content = try content()

        let shaderLibrary = ShaderLibrary.module.namespaced("ShadowMap")
        vertexShader = try shaderLibrary.vertex_depth
        fragmentShader = try shaderLibrary.fragment_depth
    }

    public var body: some Element {
        get throws {
            let depthBias = shadowMap.appliedDepthBias
            let slopeScale = shadowMap.appliedSlopeScale

            // One render pass per light, each targeting a different array slice
            ForEach(Array(0..<shadowMap.lightCount), id: \.self) { lightIndex in
                let lightVP = shadowMap.lightViewProjectionMatrices[lightIndex]
                try RenderPass(label: "Shadow Map Depth [\(lightIndex)]") {
                    try RenderPipeline(label: "Shadow Map Depth [\(lightIndex)]", vertexShader: vertexShader, fragmentShader: fragmentShader) {
                        content
                            .parameter("lightViewProjectionMatrix", functionType: .vertex, value: lightVP)
                    }
                    .depthBias(depthBias, slopeScale: slopeScale)
                    .vertexDescriptor(vertexDescriptor)
                    .depthCompare(function: shadowMap.depthCompareFunction, enabled: true)
                    .renderPipelineDescriptorTransformer { descriptor in
                        descriptor.colorAttachments[0].pixelFormat = .invalid
                        descriptor.inputPrimitiveTopology = .triangle
                    }
                }
                .renderPassDescriptorModifier { descriptor in
                    shadowMap.configureRenderPassDescriptor(descriptor, lightIndex: lightIndex)
                }
                // Later passes sample the shadow map.
                .barrierAfterPass(after: .fragment, beforeQueueStages: [.vertex, .fragment, .dispatch])
            }
        }
    }
}
