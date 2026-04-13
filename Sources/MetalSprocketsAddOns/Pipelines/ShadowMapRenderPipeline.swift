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

    /// Shadow bias to prevent acne.
    public var bias: Float

    /// The resolution of the shadow map (square).
    public let resolution: Int

    /// Creates a new shadow map with the given resolution.
    ///
    /// - Parameters:
    ///   - resolution: Width and height of the shadow map texture (default 2048).
    ///   - bias: Depth bias to prevent shadow acne (default 0.005).
    public init(resolution: Int = 2_048, bias: Float = 0.005) throws {
        self.resolution = resolution
        self.bias = bias
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
        samplerDescriptor.compareFunction = .lessEqual
        samplerDescriptor.sAddressMode = .clampToBorderColor
        samplerDescriptor.tAddressMode = .clampToBorderColor
        samplerDescriptor.borderColor = .opaqueWhite
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
            far: far
        )
        lightViewProjectionMatrix = lightProjection * lightView
    }

    /// Returns the `ShadowMapParameters` struct for passing to shaders.
    public func toParameters() -> ShadowMapParameters {
        ShadowMapParameters(
            lightViewProjectionMatrix: lightViewProjectionMatrix,
            bias: bias,
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
            try RenderPass(label: "Shadow Map Depth") {
                try RenderPipeline(vertexShader: vertexShader, fragmentShader: fragmentShader) {
                    content
                        .parameter("lightViewProjectionMatrix", functionType: .vertex, value: shadowMap.lightViewProjectionMatrix)
                }
                .vertexDescriptor(vertexDescriptor)
                .depthCompare(function: .less, enabled: true)
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
                descriptor.depthAttachment.clearDepth = 1.0
                descriptor.depthAttachment.storeAction = .store
            }
        }
    }
}

// MARK: - Element extensions for shadow map consumption

public extension Element {
    /// Attaches shadow map parameters and texture to this element for use in lit fragment shaders.
    @ElementBuilder
    func shadowMap(_ shadowMap: ShadowMap?) -> some Element {
        if let shadowMap {
            self
                .parameter("shadowMapParams", value: shadowMap.toParameters())
                .parameter("shadowMapTexture", functionType: .fragment, texture: shadowMap.depthTexture)
                .parameter("shadowMapSampler", functionType: .fragment, samplerState: shadowMap.sampler)
        }
        else {
            self
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
    static func orthographic(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> float4x4 {
        let sx = 2.0 / (right - left)
        let sy = 2.0 / (top - bottom)
        let sz = 1.0 / (near - far)  // negate: view-space Z is negative for objects in front
        let tx = -(right + left) / (right - left)
        let ty = -(top + bottom) / (top - bottom)
        let tz = near / (near - far)

        return float4x4(columns: (
            SIMD4(sx, 0, 0, 0),
            SIMD4(0, sy, 0, 0),
            SIMD4(0, 0, sz, 0),
            SIMD4(tx, ty, tz, 1)
        ))
    }
}
