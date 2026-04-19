// EdgeLinesRenderPipeline golden-image test.
// Builds a small MeshWithEdges from a SwiftMesh cube and renders its edges.

import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
@testable import MetalSprocketsAddOns
import MetalSprocketsSupport
import MetalSupport
import simd
import SwiftMesh
import Testing

private func makeCubeMeshWithEdges() -> MeshWithEdges {
    let device = _MTLCreateSystemDefaultDevice()

    // 8 cube corners.
    let positions: [SIMD3<Float>] = [
        [-0.5, -0.5, -0.5],  // 0
        [ 0.5, -0.5, -0.5],  // 1
        [ 0.5, 0.5, -0.5],  // 2
        [-0.5, 0.5, -0.5],  // 3
        [-0.5, -0.5, 0.5],  // 4
        [ 0.5, -0.5, 0.5],  // 5
        [ 0.5, 0.5, 0.5],  // 6
        [-0.5, 0.5, 0.5]   // 7
    ]

    // 12 triangles, two per cube face.
    let faces: [[Int]] = [
        // -Z
        [0, 2, 1], [0, 3, 2],
        // +Z
        [4, 5, 6], [4, 6, 7],
        // -Y
        [0, 1, 5], [0, 5, 4],
        // +Y
        [3, 6, 2], [3, 7, 6],
        // -X
        [0, 4, 7], [0, 7, 3],
        // +X
        [1, 2, 6], [1, 6, 5]
    ]

    let mesh = Mesh(positions: positions, faces: faces)
    let metalMesh = MetalMesh(mesh: mesh, device: device)
    return MeshWithEdges(metalMesh: metalMesh)
}

@Test
@MainActor
func testEdgeLinesRenderPipeline_cube() throws {
    let meshWithEdges = makeCubeMeshWithEdges()

    let projection = perspectiveProjection()
    let camera = float4x4(simd_quatf(angle: -.pi / 6, axis: SIMD3<Float>(1, 1, 0))) * float4x4(translation: SIMD3<Float>(0, 0, 3))
    let viewProjection = projection * camera.inverse
    let viewport = SIMD2<Float>(Float(defaultRenderSize.width), Float(defaultRenderSize.height))

    let renderPass = try RenderPass {
        EdgeLinesRenderPipeline(
            meshWithEdges: meshWithEdges,
            viewProjection: viewProjection,
            lineWidth: 2.0,
            viewport: viewport,
            edgeColor: [1, 1, 1, 1]
        )
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "EdgeLinesCube"))
}

@Test
@MainActor
func testEdgeLinesRenderPipeline_debugMode_renderTriangleLines() throws {
    // debugMode = true causes the pipeline to set triangle fill mode to .lines,
    // exercising an otherwise uncovered code path.
    let meshWithEdges = makeCubeMeshWithEdges()
    let projection = perspectiveProjection()
    let camera = float4x4(simd_quatf(angle: -.pi / 6, axis: SIMD3<Float>(1, 1, 0))) * float4x4(translation: SIMD3<Float>(0, 0, 3))
    let viewProjection = projection * camera.inverse
    let viewport = SIMD2<Float>(Float(defaultRenderSize.width), Float(defaultRenderSize.height))

    let renderPass = try RenderPass {
        EdgeLinesRenderPipeline(
            meshWithEdges: meshWithEdges,
            viewProjection: viewProjection,
            lineWidth: 2.0,
            viewport: viewport,
            edgeColor: [1, 0, 1, 1],
            debugMode: true
        )
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "EdgeLinesCubeDebug"))
}

@Test
@MainActor
func testEdgeLinesRenderPipeline_cubeColorizedByTriangle() throws {
    let meshWithEdges = makeCubeMeshWithEdges()

    let projection = perspectiveProjection()
    let camera = float4x4(simd_quatf(angle: -.pi / 5, axis: SIMD3<Float>(1, 0.5, 0))) * float4x4(translation: SIMD3<Float>(0, 0, 3))
    let viewProjection = projection * camera.inverse
    let viewport = SIMD2<Float>(Float(defaultRenderSize.width), Float(defaultRenderSize.height))

    let renderPass = try RenderPass {
        EdgeLinesRenderPipeline(
            meshWithEdges: meshWithEdges,
            viewProjection: viewProjection,
            lineWidth: 3.0,
            viewport: viewport,
            colorizeByTriangle: true
        )
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "EdgeLinesCubeColorized"))
}
