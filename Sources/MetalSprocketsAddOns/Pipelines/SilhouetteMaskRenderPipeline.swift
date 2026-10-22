import Metal
import MetalSprockets
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import MetalSupport
import simd
import SwiftMesh

/// Draws meshes into the current color attachment to make a silhouette mask: red is 1 (coverage) and green is the
/// fragment depth.
///
/// Put it in a `RenderPass` that targets the mask texture and clears it to 0. Use the mask as the input to
/// ``JumpFloodPipeline``. Use `.rg32Float` for depth-tested outlines; `.r8Unorm` is enough otherwise.
///
/// The depth test is off by default, so the whole object is in the mask, including parts behind other geometry.
/// That gives two outline modes:
///
/// - X-ray: ``JumpFloodOutlineRenderPipeline`` with `.always` draws the outline over everything.
/// - Depth-tested: ``JumpFloodOutlineRenderPipeline`` with `.lessEqual` (`.greaterEqual` with reverse Z) tests the
///   outline against the scene depth, so objects in front of the masked object hide it.
///
/// You can also draw the mask depth-tested against the scene, to mask only the visible parts. But then an object
/// in front that cuts across the masked object gets an outline along that edge.
public struct SilhouetteMaskRenderPipeline: Element {
    public struct Instance {
        public var mesh: MetalMesh
        public var transform: float4x4

        public init(mesh: MetalMesh, transform: float4x4 = matrix_identity_float4x4) {
            self.mesh = mesh
            self.transform = transform
        }
    }

    @MSState
    private var vertexShader = ShaderLibrary.module.namespaced("SilhouetteMask").requiredFunction(named: "vertex_main", type: VertexShader.self)

    @MSState
    private var fragmentShader = ShaderLibrary.module.namespaced("SilhouetteMask").requiredFunction(named: "fragment_main", type: FragmentShader.self)

    var instances: [Instance]
    var viewProjection: float4x4
    var depthCompareFunction: MTLCompareFunction
    var writesDepth: Bool

    public init(instances: [Instance], viewProjection: float4x4, depthCompareFunction: MTLCompareFunction = .always, writesDepth: Bool = false) {
        self.instances = instances
        self.viewProjection = viewProjection
        self.depthCompareFunction = depthCompareFunction
        self.writesDepth = writesDepth
    }

    public var body: some Element {
        get throws {
            try RenderPipeline(label: "SilhouetteMask", vertexShader: vertexShader, fragmentShader: fragmentShader) {
                ForEach(Array(instances.enumerated()), id: \.offset) { _, instance in
                    let mesh = instance.mesh
                    let (positionBuffer, positionOffset, bufferDescriptor) = try Self.positionSource(of: mesh)
                    let uniforms = SilhouetteMaskUniforms(modelViewProjection: viewProjection * instance.transform)
                    Draw { encoder in
                        encoder.setCullMode(.none)
                        for submesh in mesh.submeshes {
                            encoder.drawIndexedPrimitives(
                                primitiveType: submesh.primitiveType,
                                indexCount: submesh.indexCount,
                                indexType: submesh.indexType,
                                indexBuffer: submesh.indexBuffer.gpuAddress + UInt64(submesh.indexBufferOffset),
                                indexBufferLength: submesh.indexByteCount
                            )
                        }
                    }
                    .parameter("vertices", functionType: .vertex, buffer: positionBuffer, offset: positionOffset)
                    .parameter("vertexDescriptor", functionType: .vertex, value: bufferDescriptor)
                    .parameter("uniforms", functionType: .vertex, value: uniforms)
                    .useResources(mesh.submeshes.map(\.indexBuffer), usage: .read, stages: .vertex)
                }
            }
            .depthCompare(function: depthCompareFunction, writes: writesDepth)
        }
    }

    static func positionSource(of mesh: MetalMesh) throws -> (MTLBuffer, Int, BufferDescriptor) {
        let descriptor = mesh.vertexDescriptor
        guard let attribute = descriptor.attributes.first(where: { $0.semantic == .position }) else {
            throw MetalSprocketsError.validationError("SilhouetteMaskRenderPipeline: mesh has no position attribute")
        }
        guard attribute.format == .float3 else {
            throw MetalSprocketsError.validationError("SilhouetteMaskRenderPipeline: position format must be float3, got \(attribute.format)")
        }
        guard let layout = descriptor.layouts[attribute.bufferIndex], let buffer = mesh.vertexBuffers[attribute.bufferIndex] else {
            throw MetalSprocketsError.validationError("SilhouetteMaskRenderPipeline: missing buffer \(attribute.bufferIndex) for position")
        }
        let offset = mesh.vertexBufferOffsets[attribute.bufferIndex] ?? 0
        let bufferDescriptor = BufferDescriptor(count: UInt32(mesh.vertexCount), stride: UInt32(layout.stride), valueOffset: UInt32(attribute.offset))
        return (buffer, offset, bufferDescriptor)
    }
}
