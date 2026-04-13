@preconcurrency import Metal
import simd

// MARK: - Text Mesh

/// A renderable text mesh referencing ranges within shared vertex/index buffers.
public struct SlugTextMesh {
    /// Reference to the shared buffer storage.
    public var bufferStorage: SlugBufferStorage
    /// Offset into the vertex buffer (in bytes).
    var vertexBufferOffset: Int
    /// Offset into the index buffer (in bytes).
    var indexBufferOffset: Int
    /// Total number of indices to draw.
    public var indexCount: Int
    /// Bounding rectangle in the mesh's local coordinate space.
    public var bounds: CGRect

    /// The shared vertex buffer.
    var vertexBuffer: MTLBuffer { bufferStorage.vertexBuffer }
    /// The shared index buffer.
    var indexBuffer: MTLBuffer { bufferStorage.indexBuffer }
}

// MARK: - Buffer Storage

/// Shared storage for all text mesh vertices and indices.
public final class SlugBufferStorage {
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer

    /// Total number of indices across all meshes.
    public let totalIndexCount: Int

    init(vertexBuffer: MTLBuffer, indexBuffer: MTLBuffer, totalIndexCount: Int) {
        self.vertexBuffer = vertexBuffer
        self.indexBuffer = indexBuffer
        self.totalIndexCount = totalIndexCount
    }
}

// MARK: - Errors

public enum SlugError: Error, CustomStringConvertible {
    case bufferCreationFailed(String)
    case noMeshes

    public var description: String {
        switch self {
        case .bufferCreationFailed(let name):
            return "Failed to create Metal \(name) buffer"

        case .noMeshes:
            return "No meshes were added before finalize()"
        }
    }
}
