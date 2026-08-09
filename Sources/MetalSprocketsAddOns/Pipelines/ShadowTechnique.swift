import Metal
import MetalKit
import MetalSprockets
import MetalSprocketsSupport
import ModelIO
import simd

// MARK: - ShadowContext

/// The frame state every shadow technique needs: where the camera is, and which textures the
/// shadow passes read and write.
public struct ShadowContext {
    /// Camera transforms for the frame. Techniques derive the inverse view-projection from this
    /// rather than making callers compute it.
    public var viewTransforms: ViewTransforms

    /// The already-rendered scene colour, darkened in place by the shadow pass.
    public var colorTexture: MTLTexture

    /// The scene depth buffer, sampled to reconstruct world positions.
    public var depthTexture: MTLTexture

    /// Shadow darkness (0–1).
    public var shadowIntensity: Float

    /// Usage the colour texture must be created with: shadow passes write it from compute.
    public static let requiredColorUsage: MTLTextureUsage = [.renderTarget, .shaderRead, .shaderWrite]

    /// Usage the depth texture must be created with: shadow passes sample it from compute.
    public static let requiredDepthUsage: MTLTextureUsage = [.renderTarget, .shaderRead]

    /// Creates a shadow context, checking that the textures were created with the usage the
    /// shadow passes need.
    ///
    /// - Throws: ``MetalSprocketsError/configurationError(_:)`` if either texture is missing
    /// required usage flags.
    public init(viewTransforms: ViewTransforms, colorTexture: MTLTexture, depthTexture: MTLTexture, shadowIntensity: Float = 1.0) throws {
        guard colorTexture.usage.isSuperset(of: Self.requiredColorUsage) else {
            throw MetalSprocketsError.configurationError("Shadow colour texture needs \(Self.requiredColorUsage) usage, has \(colorTexture.usage).")
        }
        guard depthTexture.usage.isSuperset(of: Self.requiredDepthUsage) else {
            throw MetalSprocketsError.configurationError("Shadow depth texture needs \(Self.requiredDepthUsage) usage, has \(depthTexture.usage).")
        }
        self.viewTransforms = viewTransforms
        self.colorTexture = colorTexture
        self.depthTexture = depthTexture
        self.shadowIntensity = shadowIntensity
    }
}

// MARK: - ShadowTechnique

/// A way of producing shadows for a scene.
///
/// A technique owns the passes its approach needs and the order they run in relative to the scene:
/// shadow maps render depth before the scene and mask afterwards, ray tracing only runs afterwards.
/// Use ``ShadowedScene`` to wire a technique around a scene's render pass.
public protocol ShadowTechnique {
    associatedtype BeforeScene: Element
    associatedtype AfterScene: Element

    /// Passes that must run before the scene is drawn.
    func passesBeforeScene(context: ShadowContext) throws -> BeforeScene

    /// Passes that must run after the scene is drawn.
    func passesAfterScene(context: ShadowContext) throws -> AfterScene
}

// MARK: - ShadowedScene

/// Wraps a scene's render pass with the shadow passes of a ``ShadowTechnique``.
///
/// ```swift
/// try ShadowedScene(technique: technique, context: context) {
///     try RenderPass {
///         // ... scene ...
///     }
/// }
/// ```
///
/// Swapping techniques does not change this wiring.
public struct ShadowedScene<Technique, Content>: Element where Technique: ShadowTechnique, Content: Element {
    let technique: Technique
    let context: ShadowContext
    let content: Content

    public init(technique: Technique, context: ShadowContext, @ElementBuilder content: () throws -> Content) rethrows {
        self.technique = technique
        self.context = context
        self.content = try content()
    }

    public var body: some Element {
        get throws {
            try MetalSprockets.Group {
                try technique.passesBeforeScene(context: context)
                content
                try technique.passesAfterScene(context: context)
            }
        }
    }
}

// MARK: - ShadowMapTechnique

/// Shadow-mapped shadows: renders shadow casters from each light's point of view, then masks the
/// scene in screen space.
///
/// ```swift
/// let technique = try ShadowMapTechnique(lightPositions: [lightPosition], vertexDescriptor: mesh.vertexDescriptor) {
///     Draw { encoder in
///         encoder.setVertexBuffers(of: mesh)
///         encoder.draw(mesh)
///     }
///     .parameter("modelMatrix", functionType: .vertex, value: modelMatrix)
/// }
/// ```
public struct ShadowMapTechnique<Casters>: ShadowTechnique where Casters: Element {
    /// The shadow map the technique renders into, with a matrix already set per light.
    public let shadowMap: ShadowMap

    let vertexDescriptor: MDLVertexDescriptor
    let casters: Casters

    /// Creates a technique from an already-configured shadow map.
    ///
    /// - Parameters:
    ///   - shadowMap: A shadow map whose light matrices have already been set.
    ///   - vertexDescriptor: Vertex layout of the shadow-caster geometry.
    ///   - casters: Draw calls for the shadow casters, each carrying its own `modelMatrix`.
    public init(shadowMap: ShadowMap, vertexDescriptor: MDLVertexDescriptor, @ElementBuilder casters: () throws -> Casters) rethrows {
        self.shadowMap = shadowMap
        self.vertexDescriptor = vertexDescriptor
        self.casters = try casters()
    }

    /// Creates a technique for directional lights at the given world-space positions, all aiming
    /// at `target`.
    public init(
        lightPositions: [SIMD3<Float>],
        target: SIMD3<Float> = .zero,
        resolution: Int = 2_048,
        orthoSize: Float = 15,
        near: Float = 0.1,
        far: Float = 50,
        vertexDescriptor: MDLVertexDescriptor,
        @ElementBuilder casters: () throws -> Casters
    ) throws {
        var shadowMap = try ShadowMap(resolution: resolution, lightCount: lightPositions.count)
        for (index, position) in lightPositions.enumerated() {
            shadowMap.updateDirectionalLight(at: index, position: position, target: target, orthoSize: orthoSize, near: near, far: far)
        }
        try self.init(shadowMap: shadowMap, vertexDescriptor: vertexDescriptor, casters: casters)
    }

    public func passesBeforeScene(context: ShadowContext) throws -> ShadowMapDepthPass<Casters> {
        try ShadowMapDepthPass(shadowMap: shadowMap, vertexDescriptor: vertexDescriptor) {
            casters
        }
    }

    public func passesAfterScene(context: ShadowContext) throws -> ShadowMaskPass {
        try ShadowMaskPass(
            sceneDepthTexture: context.depthTexture,
            outputTexture: context.colorTexture,
            shadowMap: shadowMap,
            viewTransforms: context.viewTransforms,
            shadowIntensity: context.shadowIntensity
        )
    }
}
