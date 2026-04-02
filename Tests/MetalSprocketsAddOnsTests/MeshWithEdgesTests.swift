// MeshWithEdges Unit Tests
//
// These tests verify the edge extraction functionality of MeshWithEdges.
// Tests cover various mesh configurations and edge deduplication scenarios.

import Metal
@testable import MetalSprocketsAddOns
import MetalSprocketsSupport
import Testing

// MARK: - Test Helpers

extension Mesh {
    /// Create a simple test mesh from indices
    static func makeTestMesh(indices: [UInt32]) -> Mesh {
        let device = _MTLCreateSystemDefaultDevice()

        let vertexDescriptor = VertexDescriptor(attributes: [], layouts: [])

        // Handle empty mesh case
        guard !indices.isEmpty else {
            return Mesh(
                submeshes: [],
                vertexDescriptor: vertexDescriptor,
                vertexBuffers: []
            )
        }

        // Create index buffer
        let indexBuffer = device.makeBuffer(
            bytes: indices,
            length: indices.count * MemoryLayout<UInt32>.stride,
            options: []
        )!

        let buffer = Mesh.Buffer(
            buffer: indexBuffer,
            count: indices.count,
            offset: 0
        )

        let submesh = Mesh.Submesh(
            primitiveType: .triangle,
            indices: buffer
        )

        return Mesh(
            submeshes: [submesh],
            vertexDescriptor: vertexDescriptor,
            vertexBuffers: []
        )
    }

    /// Create a test mesh with multiple submeshes
    static func makeTestMeshWithSubmeshes(submeshIndices: [[UInt32]]) -> Mesh {
        let device = _MTLCreateSystemDefaultDevice()

        let submeshes = submeshIndices.map { indices in
            let indexBuffer = device.makeBuffer(
                bytes: indices,
                length: indices.count * MemoryLayout<UInt32>.stride,
                options: []
            )!

            let buffer = Mesh.Buffer(
                buffer: indexBuffer,
                count: indices.count,
                offset: 0
            )

            return Mesh.Submesh(
                primitiveType: .triangle,
                indices: buffer
            )
        }

        let vertexDescriptor = VertexDescriptor(attributes: [], layouts: [])

        return Mesh(
            submeshes: submeshes,
            vertexDescriptor: vertexDescriptor,
            vertexBuffers: []
        )
    }
}

// MARK: - Edge Tests

@Test
func testSingleTriangle() {
    // A single triangle should produce exactly 3 unique edges
    let indices: [UInt32] = [0, 1, 2]
    let mesh = Mesh.makeTestMesh(indices: indices)

    let meshWithEdges = MeshWithEdges(mesh: mesh)

    #expect(meshWithEdges.uniqueEdges.count == 3)

    // Verify the edges are correct (order-independent)
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
    // Triangle 1: 0-1-2
    // Triangle 2: 0-2-3
    // Should produce 5 unique edges (not 6, because edge 0-2 is shared)
    let indices: [UInt32] = [
        0, 1, 2,  // First triangle
        0, 2, 3   // Second triangle
    ]
    let mesh = Mesh.makeTestMesh(indices: indices)

    let meshWithEdges = MeshWithEdges(mesh: mesh)

    #expect(meshWithEdges.uniqueEdges.count == 5)

    let expectedEdges = Set([
        MeshWithEdges.Edge(0, 1),
        MeshWithEdges.Edge(1, 2),
        MeshWithEdges.Edge(0, 2),  // Shared edge
        MeshWithEdges.Edge(2, 3),
        MeshWithEdges.Edge(0, 3)
    ])

    let actualEdges = Set(meshWithEdges.uniqueEdges)
    #expect(actualEdges == expectedEdges)
}

@Test
func testCube() {
    // A triangulated cube has 8 vertices
    // When each of the 6 faces is divided into 2 triangles, we get:
    // - 12 wireframe edges (the actual cube edges)
    // - 6 diagonal edges (one per face from triangulation)
    // - Total: 18 unique edges
    //
    // Vertices numbered 0-7:
    //   Bottom: 0-1-2-3 (counter-clockwise)
    //   Top: 4-5-6-7 (counter-clockwise)

    let indices: [UInt32] = [
        // Front face (0-1-5-4)
        0, 1, 4,
        1, 5, 4,
        // Back face (3-2-6-7)
        3, 2, 7,
        2, 6, 7,
        // Left face (0-4-7-3)
        0, 4, 3,
        4, 7, 3,
        // Right face (1-2-6-5)
        1, 2, 5,
        2, 6, 5,
        // Bottom face (0-3-2-1)
        0, 3, 1,
        3, 2, 1,
        // Top face (4-5-6-7)
        4, 5, 7,
        5, 6, 7
    ]

    let mesh = Mesh.makeTestMesh(indices: indices)
    let meshWithEdges = MeshWithEdges(mesh: mesh)

    // Triangulated cube: 12 wireframe edges + 6 diagonal edges = 18 total
    #expect(meshWithEdges.uniqueEdges.count == 18)

    // Verify all wireframe edges are present
    let wireframeEdges: Set<MeshWithEdges.Edge> = [
        // Bottom square
        MeshWithEdges.Edge(0, 1),
        MeshWithEdges.Edge(1, 2),
        MeshWithEdges.Edge(2, 3),
        MeshWithEdges.Edge(3, 0),
        // Top square
        MeshWithEdges.Edge(4, 5),
        MeshWithEdges.Edge(5, 6),
        MeshWithEdges.Edge(6, 7),
        MeshWithEdges.Edge(7, 4),
        // Vertical edges
        MeshWithEdges.Edge(0, 4),
        MeshWithEdges.Edge(1, 5),
        MeshWithEdges.Edge(2, 6),
        MeshWithEdges.Edge(3, 7)
    ]

    let actualEdges = Set(meshWithEdges.uniqueEdges)

    // All wireframe edges should be present
    #expect(wireframeEdges.isSubset(of: actualEdges))

    // And we should have the 6 diagonal edges as well
    let diagonalEdges = actualEdges.subtracting(wireframeEdges)
    #expect(diagonalEdges.count == 6)
}

@Test
func testEdgeCanonicalOrdering() {
    // Verify that Edge(a, b) and Edge(b, a) are considered the same
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
    // Test with multiple submeshes to ensure edges are collected from all
    let submesh1: [UInt32] = [0, 1, 2]  // Triangle 1
    let submesh2: [UInt32] = [2, 3, 4]  // Triangle 2

    let mesh = Mesh.makeTestMeshWithSubmeshes(submeshIndices: [submesh1, submesh2])
    let meshWithEdges = MeshWithEdges(mesh: mesh)

    // Should have 6 unique edges total
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
    // Test with submeshes that share edges
    // Submesh 1: Triangle 0-1-2
    // Submesh 2: Triangle 1-2-3 (shares edge 1-2 with submesh 1)
    let submesh1: [UInt32] = [0, 1, 2]
    let submesh2: [UInt32] = [1, 2, 3]

    let mesh = Mesh.makeTestMeshWithSubmeshes(submeshIndices: [submesh1, submesh2])
    let meshWithEdges = MeshWithEdges(mesh: mesh)

    // Should deduplicate the shared edge 1-2
    #expect(meshWithEdges.uniqueEdges.count == 5)

    let expectedEdges = Set([
        MeshWithEdges.Edge(0, 1),
        MeshWithEdges.Edge(1, 2),  // Shared edge
        MeshWithEdges.Edge(0, 2),
        MeshWithEdges.Edge(2, 3),
        MeshWithEdges.Edge(1, 3)
    ])

    let actualEdges = Set(meshWithEdges.uniqueEdges)
    #expect(actualEdges == expectedEdges)
}

@Test
func testDegenerateTriangles() {
    // Triangles with repeated vertices (degenerate)
    // Triangle with vertices 0, 0, 1 creates edges: 0-0, 0-1, 0-1
    // Due to canonical ordering, 0-0 becomes Edge(0, 0)
    // And 0-1 appears twice but should be deduplicated
    let indices: [UInt32] = [0, 0, 1]
    let mesh = Mesh.makeTestMesh(indices: indices)
    let meshWithEdges = MeshWithEdges(mesh: mesh)

    // Should have 2 unique edges: Edge(0, 0) and Edge(0, 1)
    #expect(meshWithEdges.uniqueEdges.count == 2)

    let expectedEdges = Set([
        MeshWithEdges.Edge(0, 0),
        MeshWithEdges.Edge(0, 1)
    ])

    let actualEdges = Set(meshWithEdges.uniqueEdges)
    #expect(actualEdges == expectedEdges)
}

@Test
func testLargeIndexValues() {
    // Test with large index values to ensure UInt32 handling is correct
    let maxIndex: UInt32 = UInt32.max - 10
    let indices: [UInt32] = [
        maxIndex, maxIndex + 1, maxIndex + 2
    ]
    let mesh = Mesh.makeTestMesh(indices: indices)
    let meshWithEdges = MeshWithEdges(mesh: mesh)

    #expect(meshWithEdges.uniqueEdges.count == 3)

    let expectedEdges = Set([
        MeshWithEdges.Edge(maxIndex, maxIndex + 1),
        MeshWithEdges.Edge(maxIndex + 1, maxIndex + 2),
        MeshWithEdges.Edge(maxIndex, maxIndex + 2)
    ])

    let actualEdges = Set(meshWithEdges.uniqueEdges)
    #expect(actualEdges == expectedEdges)
}
