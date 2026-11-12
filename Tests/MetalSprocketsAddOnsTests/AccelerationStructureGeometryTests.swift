import Metal
@testable import MetalSprocketsAddOns
import MetalSupport
import SwiftMesh
import Testing

// Two submeshes packed in one index buffer, as MetalMesh's direct init allows.
@Test
func testAccelerationStructureGeometry_usesSubmeshIndexOffsetsAndTypes() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let positions: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [0, 1, 0], [1, 1, 0]]
    let vertexBufferOffset = 64
    let vertexBuffer = try #require(device.makeBuffer(length: vertexBufferOffset + positions.count * MemoryLayout<SIMD3<Float>>.stride))
    let indices: [UInt16] = [0, 1, 2, 1, 3, 2]
    let indexBuffer = try #require(device.makeBuffer(bytes: indices, length: indices.count * 2))
    let submeshes = [
        MetalMesh.Submesh(indexBuffer: indexBuffer, indexBufferOffset: 0, indexCount: 3, indexType: .uint16),
        MetalMesh.Submesh(indexBuffer: indexBuffer, indexBufferOffset: 6, indexCount: 3, indexType: .uint16)
    ]
    var mesh = MetalMesh(mesh: Mesh(positions: positions, faces: [[0, 1, 2]]), device: device)
    mesh.vertexBuffers = [0: vertexBuffer]
    mesh.vertexBufferOffsets = [0: vertexBufferOffset]
    mesh.submeshes = submeshes

    let descriptors = try AccelerationStructureManager.geometryDescriptors(for: mesh)
    #expect(descriptors.map(\.indexBufferOffset) == [0, 6])
    #expect(descriptors.map(\.indexType) == [.uint16, .uint16])
    #expect(descriptors.map(\.triangleCount) == [1, 1])
    let positionOffset = try #require(mesh.vertexDescriptor.attributes.first { $0.semantic == .position }).offset
    #expect(descriptors.allSatisfy { $0.vertexBufferOffset == vertexBufferOffset + positionOffset })
}
