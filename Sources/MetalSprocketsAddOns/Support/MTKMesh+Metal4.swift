import Metal
import MetalKit
import MetalSprockets

public extension MTL4RenderCommandEncoder {
    /// Issues indexed draw calls for every submesh of `mesh`, for `Draw` closures that also set encoder state.
    ///
    /// Prefer `Draw(mesh:)`. When you use this instead, bind the vertex buffers with `vertexBuffers(of:)` and keep
    /// the index buffers resident with `useResources(mesh.submeshes.map(\.indexBuffer.buffer), ...)`.
    func draw(_ mesh: MTKMesh, instanceCount: Int = 1) {
        for submesh in mesh.submeshes {
            let indexSize = submesh.indexType == .uint16 ? 2 : 4
            let indexBuffer = submesh.indexBuffer
            drawIndexedPrimitives(
                primitiveType: submesh.primitiveType,
                indexCount: submesh.indexCount,
                indexType: submesh.indexType,
                indexBuffer: indexBuffer.buffer.gpuAddress + UInt64(indexBuffer.offset),
                indexBufferLength: submesh.indexCount * indexSize,
                instanceCount: instanceCount
            )
        }
    }
}
