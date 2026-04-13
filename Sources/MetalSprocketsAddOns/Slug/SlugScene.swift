@preconcurrency import Metal
import simd

// MARK: - Scene

/// Bundles all GPU resources needed to render text meshes.
/// Created by `SlugTextMeshBuilder.finalize()`.
public class SlugScene: @unchecked Sendable {
    /// Shared vertex/index buffers.
    public let bufferStorage: SlugBufferStorage
    /// All meshes in the scene.
    public let meshes: [SlugTextMesh]
    /// Font texture pairs for argument buffer.
    public let fontTexturePairs: [(curveTexture: MTLTexture, bandTexture: MTLTexture)]
    /// Pre-allocated model matrices buffer (one matrix per mesh).
    public let modelMatricesBuffer: MTLBuffer

    /// Total index count across all meshes.
    public var totalIndexCount: Int { bufferStorage.totalIndexCount }

    /// Unsafe mutable view over the model matrices buffer. Prefer `withModelMatrices(_:)` for bounds-checked access.
    public var modelMatrices: UnsafeMutableBufferPointer<float4x4> {
        let ptr = modelMatricesBuffer.contents().bindMemory(to: float4x4.self, capacity: meshCount)
        return UnsafeMutableBufferPointer(start: ptr, count: meshCount)
    }

    /// Bounds-checked mutable access to model matrices via MutableSpan.
    public func withModelMatrices<R>(_ body: (inout MutableSpan<float4x4>) throws -> R) rethrows -> R {
        var span = modelMatrices.mutableSpan
        return try body(&span)
    }
    /// Number of meshes in the scene.
    public var meshCount: Int { meshes.count }

    init(
        bufferStorage: SlugBufferStorage,
        meshes: [SlugTextMesh],
        fontTexturePairs: [(curveTexture: MTLTexture, bandTexture: MTLTexture)],
        modelMatricesBuffer: MTLBuffer
    ) {
        self.bufferStorage = bufferStorage
        self.meshes = meshes
        self.fontTexturePairs = fontTexturePairs
        self.modelMatricesBuffer = modelMatricesBuffer
    }
}
