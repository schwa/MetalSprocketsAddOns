import Foundation
import SwiftMesh

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

    public var metalMesh: MetalMesh
    public var uniqueEdges: [Edge]
}

public extension MeshWithEdges {
    /// Create a MeshWithEdges from a MetalMesh by extracting its unique edges
    init(metalMesh: MetalMesh) {
        self.metalMesh = metalMesh

        // Calculate total triangle count for capacity reservation
        let totalTriangles = metalMesh.submeshes.reduce(0) { $0 + $1.indexCount / 3 }
        let estimatedEdges = (totalTriangles * 3) / 2  // Rough estimate for closed meshes

        var edgeSet = Set<Edge>(minimumCapacity: estimatedEdges)
        var uniqueEdges: [Edge] = []
        uniqueEdges.reserveCapacity(estimatedEdges)

        for submesh in metalMesh.submeshes {
            let indexBuffer = submesh.indexBuffer
            let ptr = indexBuffer.contents().assumingMemoryBound(to: UInt32.self)

            let triangleCount = submesh.indexCount / 3
            for tri in 0..<triangleCount {
                let base = tri * 3
                let i0 = ptr[base]
                let i1 = ptr[base + 1]
                let i2 = ptr[base + 2]

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
