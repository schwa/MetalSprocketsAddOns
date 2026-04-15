import Metal
import MetalKit
import MetalSprockets
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import MetalSupport
import ModelIO
import simd

// MARK: - AccelerationStructureManager

/// Builds and manages Metal acceleration structures for ray tracing.
///
/// Creates primitive acceleration structures from meshes and an instance
/// acceleration structure that combines them for scene-level ray queries.
public struct AccelerationStructureManager: @unchecked Sendable {
    /// The instance acceleration structure for the entire scene.
    public private(set) var instanceAccelerationStructure: MTLAccelerationStructure?

    /// The primitive acceleration structures (one per mesh).
    public private(set) var primitiveAccelerationStructures: [MTLAccelerationStructure] = []

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    /// A mesh instance for acceleration structure building.
    public struct Instance {
        /// Index into the meshes array passed to `build`.
        public var meshIndex: Int
        /// World transform for this instance.
        public var transform: simd_float4x4

        public init(meshIndex: Int, transform: simd_float4x4) {
            self.meshIndex = meshIndex
            self.transform = transform
        }
    }

    public init() throws {
        device = _MTLCreateSystemDefaultDevice()
        commandQueue = try device.makeCommandQueue()
            .orThrow(.resourceCreationFailure("Failed to create command queue for acceleration structure building"))
    }

    /// Builds acceleration structures from meshes and instances.
    ///
    /// - Parameters:
    ///   - meshes: The meshes to create primitive acceleration structures from.
    ///   - instances: The instances that reference meshes by index.
    public mutating func build(meshes: [MTKMesh], instances: [Instance]) throws {
        // Build primitive acceleration structures (one per unique mesh)
        var primitiveStructures: [MTLAccelerationStructure] = []
        for mesh in meshes {
            let structure = try buildPrimitiveAccelerationStructure(mesh: mesh)
            primitiveStructures.append(structure)
        }
        primitiveAccelerationStructures = primitiveStructures

        // Build instance acceleration structure
        instanceAccelerationStructure = try buildInstanceAccelerationStructure(
            primitiveStructures: primitiveStructures,
            instances: instances
        )
    }

    /// Rebuilds just the instance acceleration structure (refit) with updated transforms.
    ///
    /// This is faster than a full rebuild when only transforms change.
    public mutating func updateInstances(_ instances: [Instance]) throws {
        guard !primitiveAccelerationStructures.isEmpty else {
            throw MetalSprocketsError.resourceCreationFailure("No primitive structures built — call build() first")
        }
        instanceAccelerationStructure = try buildInstanceAccelerationStructure(
            primitiveStructures: primitiveAccelerationStructures,
            instances: instances
        )
    }

    // MARK: - Private

    private func buildPrimitiveAccelerationStructure(mesh: MTKMesh) throws -> MTLAccelerationStructure {
        var geometryDescriptors: [MTLAccelerationStructureTriangleGeometryDescriptor] = []

        for submesh in mesh.submeshes {
            let geometryDescriptor = MTLAccelerationStructureTriangleGeometryDescriptor()

            // Vertex buffer — position is always attribute 0
            let vertexBuffer = mesh.vertexBuffers[0]
            geometryDescriptor.vertexBuffer = vertexBuffer.buffer
            geometryDescriptor.vertexBufferOffset = vertexBuffer.offset
            // swiftlint:disable:next force_cast
            let layout = mesh.vertexDescriptor.layouts[0] as! MDLVertexBufferLayout
            geometryDescriptor.vertexStride = layout.stride
            geometryDescriptor.vertexFormat = .float3
            geometryDescriptor.triangleCount = submesh.indexCount / 3

            // Index buffer
            geometryDescriptor.indexBuffer = submesh.indexBuffer.buffer
            geometryDescriptor.indexBufferOffset = submesh.indexBuffer.offset
            geometryDescriptor.indexType = submesh.indexType == .uint16 ? .uint16 : .uint32

            geometryDescriptors.append(geometryDescriptor)
        }

        let descriptor = MTLPrimitiveAccelerationStructureDescriptor()
        descriptor.geometryDescriptors = geometryDescriptors

        return try buildAccelerationStructure(descriptor: descriptor)
    }

    private func buildInstanceAccelerationStructure(
        primitiveStructures: [MTLAccelerationStructure],
        instances: [Instance]
    ) throws -> MTLAccelerationStructure {
        // Create instance descriptor buffer
        let instanceDescriptorSize = MemoryLayout<MTLAccelerationStructureInstanceDescriptor>.stride
        let instanceBuffer = try device
            .makeBuffer(length: instances.count * instanceDescriptorSize, options: .storageModeShared)
            .orThrow(.resourceCreationFailure("Failed to create instance descriptor buffer"))
        instanceBuffer.label = "RT Shadow Instance Descriptors"

        let descriptorPointer = instanceBuffer.contents()
            .bindMemory(to: MTLAccelerationStructureInstanceDescriptor.self, capacity: instances.count)

        for (i, instance) in instances.enumerated() {
            var desc = MTLAccelerationStructureInstanceDescriptor()
            desc.accelerationStructureIndex = UInt32(instance.meshIndex)
            desc.intersectionFunctionTableOffset = 0
            desc.mask = 0xFF
            desc.options = .opaque

            // Convert simd_float4x4 to MTLPackedFloat4x3 (row-major 4×3)
            let m = instance.transform
            desc.transformationMatrix = MTLPackedFloat4x3(columns: (
                MTLPackedFloat3Make(m.columns.0.x, m.columns.1.x, m.columns.2.x),
                MTLPackedFloat3Make(m.columns.0.y, m.columns.1.y, m.columns.2.y),
                MTLPackedFloat3Make(m.columns.0.z, m.columns.1.z, m.columns.2.z),
                MTLPackedFloat3Make(m.columns.0.w, m.columns.1.w, m.columns.2.w)
            ))

            descriptorPointer[i] = desc
        }

        let descriptor = MTLInstanceAccelerationStructureDescriptor()
        descriptor.instanceDescriptorBuffer = instanceBuffer
        descriptor.instanceCount = instances.count
        descriptor.instancedAccelerationStructures = primitiveStructures

        return try buildAccelerationStructure(descriptor: descriptor)
    }

    private func buildAccelerationStructure(descriptor: MTLAccelerationStructureDescriptor) throws -> MTLAccelerationStructure {
        let sizes = device.accelerationStructureSizes(descriptor: descriptor)

        let accelerationStructure = try device.makeAccelerationStructure(size: sizes.accelerationStructureSize)
            .orThrow(.resourceCreationFailure("Failed to create acceleration structure"))

        let scratchBuffer = try device
            .makeBuffer(length: sizes.buildScratchBufferSize, options: .storageModePrivate)
            .orThrow(.resourceCreationFailure("Failed to create scratch buffer"))
        scratchBuffer.label = "RT Scratch"

        let commandBuffer = try commandQueue.makeCommandBuffer()
            .orThrow(.resourceCreationFailure("Failed to create command buffer for AS build"))
        let encoder = try commandBuffer.makeAccelerationStructureCommandEncoder()
            .orThrow(.resourceCreationFailure("Failed to create AS command encoder"))

        encoder.build(
            accelerationStructure: accelerationStructure,
            descriptor: descriptor,
            scratchBuffer: scratchBuffer,
            scratchBufferOffset: 0
        )
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return accelerationStructure
    }
}

// MARK: - RayTracedShadowMaskPass

/// A compute pass that uses ray tracing to determine shadow visibility.
///
/// Reconstructs world positions from the scene depth buffer, casts shadow rays
/// toward the light against the acceleration structure, and directly darkens
/// shadowed pixels in the output texture.
///
/// Usage:
/// ```swift
/// // After the main scene render pass:
/// RayTracedShadowComputePass(
///     sceneDepthTexture: sceneDepth,
///     outputTexture: drawableTexture,
///     accelerationStructureManager: accelManager,
///     lighting: lighting,
///     inverseViewProjection: inverseVP
/// )
/// ```
public struct RayTracedShadowComputePass: Element {
    let sceneDepthTexture: MTLTexture
    let outputTexture: MTLTexture
    let accelerationStructureManager: AccelerationStructureManager
    let lighting: Lighting
    let inverseViewProjection: float4x4
    let maxRayDistance: Float
    let shadowIntensity: Float
    let debug: Bool

    @MSState
    var computeKernel: ComputeKernel

    /// Creates a ray-traced shadow compute pass.
    ///
    /// - Parameters:
    ///   - sceneDepthTexture: The depth texture from the main scene render.
    ///   - outputTexture: The output texture to darken (typically the drawable texture).
    ///   - accelerationStructureManager: Manager with built acceleration structures.
    ///   - lighting: The scene lighting (shadow rays are cast toward each light).
    ///   - inverseViewProjection: Inverse of the camera's view-projection matrix.
    ///   - maxRayDistance: Maximum shadow ray distance (0 = distance to light).
    ///   - shadowIntensity: Shadow darkness (0–1, default 1).
    ///   - debug: When true, shows magenta debug overlay for shadowed areas.
    public init(
        sceneDepthTexture: MTLTexture,
        outputTexture: MTLTexture,
        accelerationStructureManager: AccelerationStructureManager,
        lighting: Lighting,
        inverseViewProjection: float4x4,
        maxRayDistance: Float = 0,
        shadowIntensity: Float = 1.0,
        debug: Bool = false
    ) throws {
        self.sceneDepthTexture = sceneDepthTexture
        self.outputTexture = outputTexture
        self.accelerationStructureManager = accelerationStructureManager
        self.lighting = lighting
        self.inverseViewProjection = inverseViewProjection
        self.maxRayDistance = maxRayDistance
        self.shadowIntensity = shadowIntensity
        self.debug = debug

        let shaderLibrary = ShaderLibrary.module.namespaced("RayTracedShadow")
        var constants = FunctionConstants()
        constants["DEBUG"] = .bool(debug)
        computeKernel = try shaderLibrary.function(named: "shadow_compute", type: ComputeKernel.self, constants: constants)
    }

    public var body: some Element {
        get throws {
            let instanceAS = accelerationStructureManager.instanceAccelerationStructure
            let primitiveStructures = accelerationStructureManager.primitiveAccelerationStructures
            var params = RayTracedShadowParameters(
                inverseViewProjection: inverseViewProjection,
                lighting: try lighting.toArgumentBuffer(),
                maxRayDistance: maxRayDistance,
                shadowIntensity: shadowIntensity
            )
            let width = outputTexture.width
            let height = outputTexture.height

            try ComputePass(label: "RT Shadow") {
                try ComputePipeline(label: "RT Shadow", computeKernel: computeKernel) {
                    try ComputeDispatch(
                        threadsPerGrid: MTLSize(width: width, height: height, depth: 1),
                        threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
                    )
                }
                .onWorkloadEnter { environmentValues in
                    guard let encoder = environmentValues.computeCommandEncoder,
                        let instanceAS
                    else {
                        return
                    }
                    encoder.setTexture(sceneDepthTexture, index: 0)
                    encoder.setTexture(outputTexture, index: 1)
                    encoder.setAccelerationStructure(instanceAS, bufferIndex: 0)
                    encoder.setBytes(&params, length: MemoryLayout<RayTracedShadowParameters>.stride, index: 1)
                    encoder.useResource(instanceAS, usage: .read)
                    for structure in primitiveStructures {
                        encoder.useResource(structure, usage: .read)
                    }
                    // Make light buffers accessible via argument buffer GPU pointers
                    encoder.useResource(lighting.lights, usage: .read)
                    encoder.useResource(lighting.lightPositions, usage: .read)
                }
            }
        }
    }
}
