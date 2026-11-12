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

    /// Optional world-space shading normals, the same size as `depthTexture`: xyz is the unit normal, and a zero
    /// vector marks pixels with none. With it, curved meshes get a smooth self-shadow edge instead of one that
    /// follows their triangles. Write it with ``SceneNormalsRenderPipeline`` into a float format such as `.rgba16Float`.
    public var normalTexture: MTLTexture?

    /// The views when the scene was drawn for several at once (such as both eyes of a visionOS immersive space).
    /// Then the textures are 2D arrays with one slice per view, and `viewTransforms` is the first view's. Nil for one
    /// view in plain 2D textures.
    public var views: StereoViews?

    /// Usage the colour texture must be created with: shadow passes write it from compute.
    public static let requiredColorUsage: MTLTextureUsage = [.renderTarget, .shaderRead, .shaderWrite]

    /// Usage the depth texture must be created with: shadow passes sample it from compute.
    public static let requiredDepthUsage: MTLTextureUsage = [.renderTarget, .shaderRead]

    /// Usage the normal texture must be created with: shadow passes read it from compute.
    public static let requiredNormalUsage: MTLTextureUsage = [.shaderRead]

    /// Creates a shadow context, checking that the textures were created with the usage the
    /// shadow passes need.
    ///
    /// - Throws: ``MetalSprocketsError/configurationError(_:)`` if either texture is missing
    /// required usage flags.
    public init(viewTransforms: ViewTransforms, colorTexture: MTLTexture, depthTexture: MTLTexture, normalTexture: MTLTexture? = nil, shadowIntensity: Float = 1.0) throws {
        guard colorTexture.usage.isSuperset(of: Self.requiredColorUsage) else {
            throw MetalSprocketsError.configurationError("Shadow colour texture needs \(Self.requiredColorUsage) usage, has \(colorTexture.usage).")
        }
        guard depthTexture.usage.isSuperset(of: Self.requiredDepthUsage) else {
            throw MetalSprocketsError.configurationError("Shadow depth texture needs \(Self.requiredDepthUsage) usage, has \(depthTexture.usage).")
        }
        if let normalTexture, !normalTexture.usage.isSuperset(of: Self.requiredNormalUsage) {
            throw MetalSprocketsError.configurationError("Shadow normal texture needs \(Self.requiredNormalUsage) usage, has \(normalTexture.usage).")
        }
        self.viewTransforms = viewTransforms
        self.colorTexture = colorTexture
        self.depthTexture = depthTexture
        self.normalTexture = normalTexture
        self.shadowIntensity = shadowIntensity
    }

    /// Creates a shadow context for a scene drawn for several views at once, one view per array slice. Draw the
    /// scene into the textures with vertex amplification (`views.configure(_:)`), then show the shadowed result with
    /// ``LayeredCompositeRenderPipeline``.
    ///
    /// - Throws: ``MetalSprocketsError/configurationError(_:)`` if a texture is missing required usage flags, or is
    /// not a 2D array with a slice per view.
    public init(views: StereoViews, colorTexture: MTLTexture, depthTexture: MTLTexture, normalTexture: MTLTexture? = nil, shadowIntensity: Float = 1.0) throws {
        try Self.validateLayered(views: views, textures: [colorTexture, depthTexture] + (normalTexture.map { [$0] } ?? []))
        let viewTransforms = ViewTransforms(projectionMatrix: views.projectionMatrices[0], cameraMatrix: views.cameraMatrices[0])
        try self.init(viewTransforms: viewTransforms, colorTexture: colorTexture, depthTexture: depthTexture, normalTexture: normalTexture, shadowIntensity: shadowIntensity)
        self.views = views
    }

    static func validateLayered(views: StereoViews, textures: [MTLTexture]) throws {
        for texture in textures where texture.textureType != .type2DArray || texture.arrayLength < views.count {
            throw MetalSprocketsError.configurationError("Layered shadow textures must be 2D arrays with \(views.count) slices; \(texture.label ?? "a texture") is \(texture.textureType.rawValue) with \(texture.arrayLength).")
        }
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
///     Draw(mesh: mesh)
///         .vertexBuffers(of: mesh)
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
        if let views = context.views {
            return try ShadowMaskPass(
                sceneDepthTexture: context.depthTexture,
                outputTexture: context.colorTexture,
                shadowMap: shadowMap,
                views: views,
                shadowIntensity: context.shadowIntensity,
                sceneNormalTexture: context.normalTexture
            )
        }
        return try ShadowMaskPass(
            sceneDepthTexture: context.depthTexture,
            outputTexture: context.colorTexture,
            shadowMap: shadowMap,
            viewTransforms: context.viewTransforms,
            shadowIntensity: context.shadowIntensity,
            sceneNormalTexture: context.normalTexture
        )
    }
}
