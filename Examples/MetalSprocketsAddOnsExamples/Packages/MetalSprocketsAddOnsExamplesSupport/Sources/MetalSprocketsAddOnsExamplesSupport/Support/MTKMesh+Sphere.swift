import MetalKit
import MetalSupport

extension MTKMesh {
    /// A UV sphere with a chosen tessellation. `MTKMesh.sphere(extent:)` is fixed at 48 segments.
    ///
    /// Ray-traced self-shadowing follows the flat triangles, so coarse spheres show a stepped
    /// shadow edge (#58). More segments make the steps smaller.
    static func sphere(radius: Float, segments: UInt32) -> MTKMesh {
        let device = _MTLCreateSystemDefaultDevice()
        let allocator = MTKMeshBufferAllocator(device: device)
        let mdlMesh = MDLMesh(
            sphereWithExtent: [radius, radius, radius],
            segments: [segments, segments],
            inwardNormals: false,
            geometryType: .triangles,
            allocator: allocator
        )
        do {
            return try MTKMesh(mesh: mdlMesh, device: device)
        } catch {
            fatalError("\(error)")
        }
    }
}
