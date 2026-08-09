// DebugRenderPipeline golden-image tests.

import CoreGraphics
import GeometryLite3D
import Metal
import MetalKit
import MetalSprockets
@testable import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import MetalSupport
import simd
import Testing

private func renderDebugMode(_ mode: DebugShadersMode, mesh: MTKMesh) throws -> CGImage {
    let projection = perspectiveProjection()
    let cameraMatrix = float4x4(translation: SIMD3<Float>(0, 0, 3))
    let viewMatrix = cameraMatrix.inverse
    let viewProjection = projection * viewMatrix
    let modelMatrix = float4x4(simd_quatf(angle: .pi / 5, axis: simd_normalize(SIMD3<Float>(1, 1, 0))))
    let normalMatrix = float3x3(
        modelMatrix.columns.0.xyz,
        modelMatrix.columns.1.xyz,
        modelMatrix.columns.2.xyz
    )

    let renderPass = try RenderPass {
        try DebugRenderPipeline(
            modelMatrix: modelMatrix,
            normalMatrix: normalMatrix,
            debugMode: mode,
            lightPosition: [2, 2, 3],
            cameraPosition: cameraMatrix.translation,
            viewProjectionMatrix: viewProjection
        ) {
            Draw { encoder in
                encoder.setVertexBuffers(of: mesh)
                encoder.draw(mesh)
            }
        }
        .vertexDescriptor(mesh.vertexDescriptor)
        .depthCompare(function: .less, enabled: true)
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    return try renderer.render(renderPass).cgImage
}

@Test
@MainActor
func testDebugRenderPipeline_normalMode() throws {
    let mesh = try makeSphereMeshWithTangents()
    let image = try renderDebugMode(.normal, mesh: mesh)
    #expect(try image.fractionOfBlackPixels() < 0.95)
    #expect(try image.isEqualToGoldenImage(named: "DebugNormal"))
}

@Test
@MainActor
func testDebugRenderPipeline_localPositionMode() throws {
    let mesh = try makeBoxMeshWithTangents()
    let image = try renderDebugMode(.localPosition, mesh: mesh)
    #expect(try image.fractionOfBlackPixels() < 0.95)
    #expect(try image.isEqualToGoldenImage(named: "DebugLocalPosition"))
}

@Test
@MainActor
func testDebugRenderPipeline_faceNormalMode() throws {
    let mesh = try makeBoxMeshWithTangents()
    let image = try renderDebugMode(.faceNormal, mesh: mesh)
    #expect(try image.fractionOfBlackPixels() < 0.95)
    #expect(try image.isEqualToGoldenImage(named: "DebugFaceNormal"))
}
