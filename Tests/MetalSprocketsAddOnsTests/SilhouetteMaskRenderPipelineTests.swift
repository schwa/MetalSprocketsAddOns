import CoreGraphics
import Metal
import MetalSprockets
@testable import MetalSprocketsAddOns
import MetalSprocketsSupport
import MetalSupport
import simd
import SwiftMesh
import Testing

/// Two quads in NDC, left and right, in separate submeshes.
private func makeTwoQuadMesh() -> MetalMesh {
    let device = _MTLCreateSystemDefaultDevice()
    let positions: [SIMD3<Float>] = [
        [-0.8, -0.4, 0], [-0.2, -0.4, 0], [-0.2, 0.4, 0], [-0.8, 0.4, 0],
        [0.2, -0.4, 0], [0.8, -0.4, 0], [0.8, 0.4, 0], [0.2, 0.4, 0]
    ]
    let faces = [[0, 1, 2], [0, 2, 3], [4, 5, 6], [4, 6, 7]].map { HalfEdgeTopology.FaceDefinition(outer: $0) }
    let topology = HalfEdgeTopology(vertexCount: positions.count, faces: faces)
    let submeshes = [
        Mesh.Submesh(faces: [HalfEdgeTopology.FaceID(raw: 0), HalfEdgeTopology.FaceID(raw: 1)]),
        Mesh.Submesh(faces: [HalfEdgeTopology.FaceID(raw: 2), HalfEdgeTopology.FaceID(raw: 3)])
    ]
    return MetalMesh(mesh: Mesh(topology: topology, positions: positions, submeshes: submeshes), device: device)
}

@Test(.requiresMetal4)
@MainActor
func testSilhouetteMask_coversAllSubmeshes() throws {
    let mesh = makeTwoQuadMesh()
    #expect(mesh.submeshes.count == 2)

    let renderPass = try RenderPass {
        SilhouetteMaskRenderPipeline(instances: [.init(mesh: mesh)], viewProjection: matrix_identity_float4x4)
    }
    let size = 100
    let renderer = try OffscreenRenderer(size: CGSize(width: size, height: size))
    let image = try renderer.render(renderPass).cgImage

    // Quad centres: x = -0.5 and 0.5 in NDC → pixel 25 and 75.
    #expect(try image.luminance(atX: 25, y: 50) > 0.99)
    #expect(try image.luminance(atX: 75, y: 50) > 0.99)
    #expect(try image.luminance(atX: 50, y: 50) < 0.01)
    #expect(try image.luminance(atX: 25, y: 5) < 0.01)
}

@Test(.requiresMetal4)
@MainActor
func testSilhouetteMask_appliesInstanceTransform() throws {
    let mesh = makeTwoQuadMesh()
    let shiftUp = float4x4(translation: [0, 0.5, 0])

    let renderPass = try RenderPass {
        SilhouetteMaskRenderPipeline(instances: [.init(mesh: mesh, transform: shiftUp)], viewProjection: matrix_identity_float4x4)
    }
    let size = 100
    let renderer = try OffscreenRenderer(size: CGSize(width: size, height: size))
    let image = try renderer.render(renderPass).cgImage

    // Shifted up by 0.5 NDC: quad now spans y 0.1...0.9 → top half of the image.
    #expect(try image.luminance(atX: 25, y: 20) > 0.99)
    #expect(try image.luminance(atX: 25, y: 80) < 0.01)
}
