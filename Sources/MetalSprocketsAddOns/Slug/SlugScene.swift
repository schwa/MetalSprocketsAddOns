#if arch(arm64)

import Metal
import simd

// MARK: - Scene

/// Bundles all GPU resources needed to render text meshes.
/// Created by `SlugTextMeshBuilder.finalize()`.
///
/// - Important: A scene is not `Sendable`. It owns shared GPU storage (notably the model
/// matrices buffer) with no synchronization, and `MTLTexture` itself is not `Sendable`, so a
/// scene must stay within the isolation domain that created it.
public class SlugScene {
    /// The device that owns every buffer and texture in this scene.
    public let device: MTLDevice
    /// All meshes in the scene, in the order they were built.
    public let meshes: [SlugTextMesh]

    /// Shared vertex/index buffers.
    let bufferStorage: SlugBufferStorage
    /// Font texture pairs, indexed by the font index stored in each vertex.
    let fontTexturePairs: [(curveTexture: MTLTexture, bandTexture: MTLTexture)]
    /// Pre-allocated model matrices buffer, one matrix per mesh.
    let modelMatricesBuffer: MTLBuffer

    /// Total index count across all meshes.
    var totalIndexCount: Int { bufferStorage.totalIndexCount }

    // The buffer memory outlives every scoped accessor below, so binding it per call is safe;
    // the pointer itself must never escape.
    private var modelMatricesPointer: UnsafeMutableBufferPointer<float4x4> {
        let ptr = modelMatricesBuffer.contents().bindMemory(to: float4x4.self, capacity: meshCount)
        return UnsafeMutableBufferPointer(start: ptr, count: meshCount)
    }

    /// Bounds-checked mutable access to the model matrices, one per mesh.
    public func withModelMatrices<R>(_ body: (inout MutableSpan<float4x4>) throws -> R) rethrows -> R {
        var span = modelMatricesPointer.mutableSpan
        return try body(&span)
    }

    /// The model matrix for the mesh at `index`.
    public func modelMatrix(at index: Int) -> float4x4 {
        precondition(index >= 0 && index < meshCount, "model matrix index out of range")
        return modelMatricesPointer[index]
    }
    /// Number of meshes in the scene.
    public var meshCount: Int { meshes.count }

    init(
        device: MTLDevice,
        bufferStorage: SlugBufferStorage,
        meshes: [SlugTextMesh],
        fontTexturePairs: [(curveTexture: MTLTexture, bandTexture: MTLTexture)],
        modelMatricesBuffer: MTLBuffer
    ) {
        self.device = device
        self.bufferStorage = bufferStorage
        self.meshes = meshes
        self.fontTexturePairs = fontTexturePairs
        self.modelMatricesBuffer = modelMatricesBuffer
    }
}

#endif // arch(arm64)
