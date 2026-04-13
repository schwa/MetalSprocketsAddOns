import Metal
import MetalKit
import MetalSprockets
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import ModelIO
import simd

// MARK: - ShadowMap

/// Manages shadow map texture creation and light matrix computation.
public struct ShadowMap {
    /// The depth texture rendered from the light's perspective.
    public let depthTexture: MTLTexture

    /// The sampler used for shadow map lookups (comparison sampler).
    public let sampler: MTLSamplerState

    /// The light's view-projection matrix.
    public var lightViewProjectionMatrix: simd_float4x4

    /// Constant depth bias to prevent acne.
    public var depthBias: Float

    /// Slope-scale depth bias — scales with the surface slope relative to the light.
    public var slopeScale: Float

    /// The resolution of the shadow map (square).
    public let resolution: Int

    /// Whether to use inverse Z (reversed depth buffer) for better precision.
    public let useInverseZ: Bool

    /// Creates a new shadow map with the given resolution.
    ///
    /// - Parameters:
    ///   - resolution: Width and height of the shadow map texture (default 2048).
    ///   - depthBias: Constant depth bias to prevent shadow acne.
    ///   - slopeScale: Slope-scale depth bias.
    ///   - useInverseZ: Use inverse Z (reversed depth) for better precision (default true).
    public init(resolution: Int = 2_048, depthBias: Float = 2.0, slopeScale: Float = 2.0, useInverseZ: Bool = true) throws {
        self.resolution = resolution
        self.depthBias = depthBias
        self.slopeScale = slopeScale
        self.useInverseZ = useInverseZ
        self.lightViewProjectionMatrix = .identity

        let device = _MTLCreateSystemDefaultDevice()

        // Create depth texture
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: resolution,
            height: resolution,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        depthTexture = try device.makeTexture(descriptor: descriptor)
            .orThrow(.resourceCreationFailure("Failed to create shadow map depth texture"))
        depthTexture.label = "Shadow Map Depth"

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

    /// Computes an orthographic light view-projection matrix for a directional light.
    ///
    /// - Parameters:
    ///   - lightPosition: World-space position of the light.
    ///   - target: The point the light looks at.
    ///   - up: Up vector for the light's view (default [0,1,0]).
    ///   - orthoSize: Half-extent of the orthographic frustum.
    ///   - near: Near plane distance.
    ///   - far: Far plane distance.
    public mutating func updateDirectionalLight(
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
        lightViewProjectionMatrix = lightProjection * lightView
    }

    /// Returns the `ShadowMapParameters` struct for passing to shaders.
    public func toParameters() -> ShadowMapParameters {
        ShadowMapParameters(
            lightViewProjectionMatrix: lightViewProjectionMatrix,
            mapSize: Float(resolution)
        )
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
        self.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)!

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
            try RenderPass(label: "Shadow Map Depth") {
                try RenderPipeline(label: "Shadow Map Depth", vertexShader: vertexShader, fragmentShader: fragmentShader) {
                    content
                        .parameter("lightViewProjectionMatrix", functionType: .vertex, value: shadowMap.lightViewProjectionMatrix)
                }
                .onWorkloadEnter { environmentValues in
                    let encoder = environmentValues.renderCommandEncoder!
                    encoder.setDepthBias(depthBias, slopeScale: slopeScale, clamp: 0)
                }
                .vertexDescriptor(vertexDescriptor)
                .depthCompare(function: useInverseZ ? .greaterEqual : .lessEqual, enabled: true)
                .renderPipelineDescriptorModifier { descriptor in
                    descriptor.colorAttachments[0].pixelFormat = .invalid
                    descriptor.depthAttachmentPixelFormat = .depth32Float
                }
            }
            .renderPassDescriptorModifier { descriptor in
                // Depth-only pass: no color attachment
                descriptor.colorAttachments[0].texture = nil
                descriptor.colorAttachments[0].loadAction = .dontCare
                descriptor.colorAttachments[0].storeAction = .dontCare
                descriptor.depthAttachment.texture = shadowMap.depthTexture
                descriptor.depthAttachment.loadAction = .clear
                descriptor.depthAttachment.clearDepth = shadowMap.useInverseZ ? 0.0 : 1.0
                descriptor.depthAttachment.storeAction = .store
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
