// MeshWithEdges Unit Tests
//
// These tests verify the edge extraction functionality of MeshWithEdges.
// Tests cover various mesh configurations and edge deduplication scenarios.

import Metal
@testable import MetalSprocketsAddOns
import MetalSprocketsSupport
import MetalSupport
import SwiftMesh
import Testing

// MARK: - Test Helpers

/// Creates a MetalMesh from raw triangle indices for testing edge extraction.
/// Generates dummy positions so the mesh is valid, but geometry doesn't matter for edge tests.
private func makeTestMetalMesh(indices: [UInt32]) -> MetalMesh {
    let device = _MTLCreateSystemDefaultDevice()
    guard !indices.isEmpty else {
        // Build a trivial empty mesh
        let maxVertex = 1
        let positions = (0..<maxVertex).map { SIMD3<Float>(Float($0), 0, 0) }
        let mesh = Mesh(positions: positions, faces: [] as [[Int]])
        return MetalMesh(mesh: mesh, device: device)
    }

    let maxVertex = Int(indices.max()!) + 1
    let positions = (0..<maxVertex).map { SIMD3<Float>(Float($0), 0, 0) }

    // Build faces from triangle indices
    var faces: [[Int]] = []
    for i in stride(from: 0, to: indices.count, by: 3) {
        faces.append([Int(indices[i]), Int(indices[i + 1]), Int(indices[i + 2])])
    }

    let mesh = Mesh(positions: positions, faces: faces)
    return MetalMesh(mesh: mesh, device: device)
}

/// Creates a MetalMesh with multiple submeshes for testing.
private func makeTestMetalMeshWithSubmeshes(submeshIndices: [[UInt32]]) -> MetalMesh {
    let device = _MTLCreateSystemDefaultDevice()

    let allIndices = submeshIndices.flatMap { $0 }
    let maxVertex = Int(allIndices.max()!) + 1
    let positions = (0..<maxVertex).map { SIMD3<Float>(Float($0), 0, 0) }

    // Build faces with submesh assignment
    var allFaces: [[Int]] = []
    var submeshDefs: [Mesh.Submesh] = []
    var faceIndex = 0

    for groupIndices in submeshIndices {
        var faceIDs: [HalfEdgeTopology.FaceID] = []
        for i in stride(from: 0, to: groupIndices.count, by: 3) {
            allFaces.append([Int(groupIndices[i]), Int(groupIndices[i + 1]), Int(groupIndices[i + 2])])
            faceIDs.append(HalfEdgeTopology.FaceID(raw: faceIndex))
            faceIndex += 1
        }
        submeshDefs.append(Mesh.Submesh(faces: faceIDs))
    }

    let faceDefs = allFaces.map { HalfEdgeTopology.FaceDefinition(outer: $0) }
    let topology = HalfEdgeTopology(vertexCount: maxVertex, faces: faceDefs)
    let mesh = Mesh(topology: topology, positions: positions, submeshes: submeshDefs)
    return MetalMesh(mesh: mesh, device: device)
}

// MARK: - Edge Tests

@Test
func testSingleTriangle() {
    let mesh = makeTestMetalMesh(indices: [0, 1, 2])
    let meshWithEdges = MeshWithEdges(metalMesh: mesh)

    #expect(meshWithEdges.uniqueEdges.count == 3)

    let expectedEdges = Set([
        MeshWithEdges.Edge(0, 1),
        MeshWithEdges.Edge(1, 2),
        MeshWithEdges.Edge(2, 0)
    ])

    let actualEdges = Set(meshWithEdges.uniqueEdges)
    #expect(actualEdges == expectedEdges)
}

@Test
func testQuadTwoTriangles() {
    // A quad made of 2 triangles sharing an edge
    // Should produce 5 unique edges (not 6, because edge 0-2 is shared)
    let mesh = makeTestMetalMesh(indices: [
        0, 1, 2,
        0, 2, 3
    ])
    let meshWithEdges = MeshWithEdges(metalMesh: mesh)

    #expect(meshWithEdges.uniqueEdges.count == 5)

    let expectedEdges = Set([
        MeshWithEdges.Edge(0, 1),
        MeshWithEdges.Edge(1, 2),
        MeshWithEdges.Edge(0, 2),
        MeshWithEdges.Edge(2, 3),
        MeshWithEdges.Edge(0, 3)
    ])

    let actualEdges = Set(meshWithEdges.uniqueEdges)
    #expect(actualEdges == expectedEdges)
}

@Test
func testCube() {
    // A cube has 6 quad faces. Each quad is triangulated into 2 triangles = 12 triangles.
    // A triangulated cube has 18 unique edges: 12 wireframe + 6 diagonals.
    let device = _MTLCreateSystemDefaultDevice()
    let swiftMesh = Mesh.box()
    let metalMesh = MetalMesh(mesh: swiftMesh, device: device)
    let meshWithEdges = MeshWithEdges(metalMesh: metalMesh)

    // 8 vertices, 12 triangles, 18 unique edges
    #expect(meshWithEdges.uniqueEdges.count == 18)
}

@Test
func testEdgeCanonicalOrdering() {
    let edge1 = MeshWithEdges.Edge(5, 10)
    let edge2 = MeshWithEdges.Edge(10, 5)

    #expect(edge1 == edge2)
    #expect(edge1.startIndex == 5)
    #expect(edge1.endIndex == 10)
    #expect(edge2.startIndex == 5)
    #expect(edge2.endIndex == 10)
}

@Test
func testMultipleSubmeshes() {
    let mesh = makeTestMetalMeshWithSubmeshes(submeshIndices: [
        [0, 1, 2],
        [2, 3, 4]
    ])
    let meshWithEdges = MeshWithEdges(metalMesh: mesh)

    #expect(meshWithEdges.uniqueEdges.count == 6)

    let expectedEdges = Set([
        MeshWithEdges.Edge(0, 1),
        MeshWithEdges.Edge(1, 2),
        MeshWithEdges.Edge(0, 2),
        MeshWithEdges.Edge(2, 3),
        MeshWithEdges.Edge(3, 4),
        MeshWithEdges.Edge(2, 4)
    ])

    let actualEdges = Set(meshWithEdges.uniqueEdges)
    #expect(actualEdges == expectedEdges)
}

@Test
func testMultipleSubmeshesWithSharedEdges() {
    let mesh = makeTestMetalMeshWithSubmeshes(submeshIndices: [
        [0, 1, 2],
        [1, 2, 3]
    ])
    let meshWithEdges = MeshWithEdges(metalMesh: mesh)

    #expect(meshWithEdges.uniqueEdges.count == 5)

    let expectedEdges = Set([
        MeshWithEdges.Edge(0, 1),
        MeshWithEdges.Edge(1, 2),
        MeshWithEdges.Edge(0, 2),
        MeshWithEdges.Edge(2, 3),
        MeshWithEdges.Edge(1, 3)
    ])

    let actualEdges = Set(meshWithEdges.uniqueEdges)
    #expect(actualEdges == expectedEdges)
}
