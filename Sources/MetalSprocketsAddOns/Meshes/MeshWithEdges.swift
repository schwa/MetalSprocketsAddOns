import Foundation

public struct MeshWithEdges {
    public struct Edge: Hashable {
        public var startIndex: UInt32
        public var endIndex: UInt32

        public init(_ a: UInt32, _ b: UInt32) {
            // Canonical ordering: smaller index first
            if a < b {
                startIndex = a
                endIndex = b
            } else {
                startIndex = b
                endIndex = a
            }
        }
    }

    var mesh: Mesh
    var uniqueEdges: [Edge]
}

public extension MeshWithEdges {
    /// Create a MeshWithEdges from a Mesh by extracting its unique edges
    init(mesh: Mesh) {
        self.mesh = mesh

        var edgeSet = Set<Edge>()
        var uniqueEdges: [Edge] = []

        for submesh in mesh.submeshes {
            let indexBuffer = submesh.indices.buffer
            let offset = submesh.indices.offset
            let ptr = indexBuffer.contents().advanced(by: offset).assumingMemoryBound(to: UInt32.self)

            let triangleCount = submesh.indices.count / 3
            for triangleIndex in 0..<triangleCount {
                let i0 = ptr[triangleIndex * 3 + 0]
                let i1 = ptr[triangleIndex * 3 + 1]
                let i2 = ptr[triangleIndex * 3 + 2]

                let edges = [
                    Edge(i0, i1),
                    Edge(i1, i2),
                    Edge(i2, i0)
                ]

                for edge in edges where edgeSet.insert(edge).inserted {
                    uniqueEdges.append(Edge(edge.startIndex, edge.endIndex))
                }
            }
        }

        self.uniqueEdges = uniqueEdges
    }
}
