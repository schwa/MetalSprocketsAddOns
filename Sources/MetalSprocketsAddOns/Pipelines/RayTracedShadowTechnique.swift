import Metal
import MetalKit
import MetalSprockets
import MetalSprocketsSupport
import simd

/// Ray-traced shadows behind the shared ``ShadowTechnique`` entry point.
///
/// Nothing has to run before the scene — the compute pass traces shadow rays against the
/// acceleration structures afterwards. The technique holds the acceleration structure manager, so
/// the instance and primitive structures stay alive for as long as the technique does.
///
/// ```swift
/// let technique = try RayTracedShadowTechnique(meshes: [mesh], instances: instances, lighting: lighting)
/// try ShadowedScene(technique: technique, context: context) {
///     try RenderPass { /* ... scene ... */ }
/// }
/// ```
public struct RayTracedShadowTechnique: ShadowTechnique {
    /// The acceleration structures shadow rays are traced against.
    public let accelerationStructureManager: AccelerationStructureManager

    let lighting: Lighting
    let maxRayDistance: Float

    /// Creates a technique from already-built acceleration structures.
    public init(accelerationStructureManager: AccelerationStructureManager, lighting: Lighting, maxRayDistance: Float = 0) {
        self.accelerationStructureManager = accelerationStructureManager
        self.lighting = lighting
        self.maxRayDistance = maxRayDistance
    }

    /// Creates a technique, building acceleration structures for the given meshes and instances.
    public init(
        meshes: [MTKMesh],
        instances: [AccelerationStructureManager.Instance],
        lighting: Lighting,
        maxRayDistance: Float = 0
    ) throws {
        var manager = try AccelerationStructureManager()
        try manager.build(meshes: meshes, instances: instances)
        self.init(accelerationStructureManager: manager, lighting: lighting, maxRayDistance: maxRayDistance)
    }

    public func passesBeforeScene(context: ShadowContext) -> EmptyElement {
        EmptyElement()
    }

    public func passesAfterScene(context: ShadowContext) throws -> RayTracedShadowComputePass {
        try RayTracedShadowComputePass(
            sceneDepthTexture: context.depthTexture,
            outputTexture: context.colorTexture,
            accelerationStructureManager: accelerationStructureManager,
            lighting: lighting,
            viewTransforms: context.viewTransforms,
            maxRayDistance: maxRayDistance,
            shadowIntensity: context.shadowIntensity
        )
    }
}
