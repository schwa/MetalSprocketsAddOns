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

        // Calculate total triangle count for capacity reservation
        let totalTriangles = mesh.submeshes.reduce(0) { $0 + $1.indices.count / 3 }
        let estimatedEdges = (totalTriangles * 3) / 2  // Rough estimate for closed meshes

        var edgeSet = Set<Edge>(minimumCapacity: estimatedEdges)
        var uniqueEdges: [Edge] = []
        uniqueEdges.reserveCapacity(estimatedEdges)

        for submesh in mesh.submeshes {
            let indexBuffer = submesh.indices.buffer
            let offset = submesh.indices.offset
            var ptr = indexBuffer.contents().advanced(by: offset).assumingMemoryBound(to: UInt32.self)

            let triangleCount = submesh.indices.count / 3
            for _ in 0..<triangleCount {
                let i0 = ptr[0]
                let i1 = ptr[1]
                let i2 = ptr[2]
                ptr += 3

                // Process edges directly without temporary array
                let edge0 = Edge(i0, i1)
                if edgeSet.insert(edge0).inserted {
                    uniqueEdges.append(edge0)
                }

                let edge1 = Edge(i1, i2)
                if edgeSet.insert(edge1).inserted {
                    uniqueEdges.append(edge1)
                }

                let edge2 = Edge(i2, i0)
                if edgeSet.insert(edge2).inserted {
                    uniqueEdges.append(edge2)
                }
            }
        }

        self.uniqueEdges = uniqueEdges
    }
}
