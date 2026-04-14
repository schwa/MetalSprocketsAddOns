import Metal
import MetalKit
import MetalSprockets
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
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
        samplerDescriptor.compareFunction = useInverseZ ? .greaterEqual : .lessEqual
        samplerDescriptor.sAddressMode = .clampToBorderColor
        samplerDescriptor.tAddressMode = .clampToBorderColor
        samplerDescriptor.borderColor = useInverseZ ? .opaqueBlack : .opaqueWhite
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
/// Usage:
/// ```swift
/// ShadowMapDepthPass(shadowMap: shadowMap) {
///     // Draw calls for shadow casters — same geometry, just needs positions
///     Draw { encoder in
///         encoder.setVertexBuffers(of: mesh)
///         encoder.draw(mesh)
///     }
///     .parameter("modelMatrix", functionType: .vertex, value: modelMatrix)
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
            let biasSign: Float = shadowMap.useInverseZ ? -1 : 1
            let depthBias = shadowMap.depthBias * biasSign
            let slopeScale = shadowMap.slopeScale * biasSign
            let useInverseZ = shadowMap.useInverseZ

            // One render pass per light, each targeting a different array slice
            try ForEach(Array(0..<shadowMap.lightCount), id: \.self) { lightIndex in
                let lightVP = shadowMap.lightViewProjectionMatrices[lightIndex]
                try RenderPass(label: "Shadow Map Depth [\(lightIndex)]") {
                    try RenderPipeline(label: "Shadow Map Depth [\(lightIndex)]", vertexShader: vertexShader, fragmentShader: fragmentShader) {
                        content
                            .parameter("lightViewProjectionMatrix", functionType: .vertex, value: lightVP)
                    }
                    .onWorkloadEnter { environmentValues in
                        guard let encoder = environmentValues.renderCommandEncoder
                        else { return }
                        encoder.setDepthBias(depthBias, slopeScale: slopeScale, clamp: 0)
                    }
                    .vertexDescriptor(vertexDescriptor)
                    .depthCompare(function: useInverseZ ? .greaterEqual : .lessEqual, enabled: true)
                    .renderPipelineDescriptorModifier { descriptor in
                        descriptor.colorAttachments[0].pixelFormat = .invalid
                        descriptor.depthAttachmentPixelFormat = .depth32Float
                        descriptor.inputPrimitiveTopology = .triangle
                    }
                }
                .renderPassDescriptorModifier { descriptor in
                    descriptor.colorAttachments[0].texture = nil
                    descriptor.colorAttachments[0].loadAction = .dontCare
                    descriptor.colorAttachments[0].storeAction = .dontCare
                    descriptor.depthAttachment.texture = shadowMap.depthTexture
                    descriptor.depthAttachment.slice = lightIndex
                    descriptor.depthAttachment.loadAction = .clear
                    descriptor.depthAttachment.clearDepth = useInverseZ ? 0.0 : 1.0
                    descriptor.depthAttachment.storeAction = .store
                    descriptor.renderTargetArrayLength = 1
                }
            }
        }
    }
}

// MARK: - Matrix helpers

extension float4x4 {
    /// Creates a look-at view matrix.
    static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> float4x4 {
        let z = normalize(eye - target) // camera looks along -Z
        let x = normalize(cross(up, z))
        let y = cross(z, x)

        return float4x4(columns: (
            SIMD4(x.x, y.x, z.x, 0),
            SIMD4(x.y, y.y, z.y, 0),
            SIMD4(x.z, y.z, z.z, 0),
            SIMD4(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
        ))
    }

    /// Creates an orthographic projection matrix.
    /// - Parameter inverseZ: When true, near maps to 1.0 and far maps to 0.0 (reversed depth).
    static func orthographic(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float, inverseZ: Bool = true) -> float4x4 {
        let sx = 2.0 / (right - left)
        let sy = 2.0 / (top - bottom)
        let sz: Float
        let tz: Float
        if inverseZ {
            sz = 1.0 / (far - near)   // inverse Z: near → 1, far → 0
            tz = far / (far - near)
        } else {
            sz = 1.0 / (near - far)   // standard Z: near → 0, far → 1
            tz = near / (near - far)
        }
        let tx = -(right + left) / (right - left)
        let ty = -(top + bottom) / (top - bottom)

        return float4x4(columns: (
            SIMD4(sx, 0, 0, 0),
            SIMD4(0, sy, 0, 0),
            SIMD4(0, 0, sz, 0),
            SIMD4(tx, ty, tz, 1)
        ))
    }
}
