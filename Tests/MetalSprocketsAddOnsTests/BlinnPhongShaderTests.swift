// BlinnPhongShader golden-image tests. Exercises BlinnPhongShader, BlinnPhongMaterial,
// blinnPhongMaterial/blinnPhongMatrices modifiers, and Lighting.

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

@Test(.requiresMetal4)
@MainActor
func testBlinnPhongShader_litBox() throws {
    let mesh = try makeBoxMeshWithTangents()

    let projection = perspectiveProjection()
    let cameraMatrix = float4x4(translation: SIMD3<Float>(0, 0, 3))
    let viewMatrix = cameraMatrix.inverse
    let modelMatrix = float4x4(simd_quatf(angle: .pi / 5, axis: simd_normalize(SIMD3<Float>(1, 1, 0))))

    let lighting = try Lighting(
        ambientLightColor: [0.1, 0.1, 0.15],
        lights: [
            ([2, 2, 3], Light(type: .point, color: [1, 1, 1], intensity: 8))
        ]
    )

    let material = BlinnPhongMaterial(
        ambient: .color([0.1, 0.05, 0.05]),
        diffuse: .color([0.7, 0.2, 0.2]),
        specular: .color([0.9, 0.9, 0.9]),
        shininess: 32
    )

    let renderPass = try RenderPass {
        try BlinnPhongShader {
            try Draw(mesh: mesh)
            .vertexBuffers(of: mesh)
            .blinnPhongMaterial(material)
            .blinnPhongMatrices(
                projectionMatrix: projection,
                viewMatrix: viewMatrix,
                modelMatrix: modelMatrix,
                cameraMatrix: cameraMatrix
            )
            .lighting(lighting)
        }
        .vertexDescriptor(mesh.vertexDescriptor)
        .depthCompare(function: .less, enabled: true)
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.fractionOfBlackPixels() < 0.95)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "BlinnPhongBox"))
}

@Test(.requiresMetal4)
@MainActor
func testBlinnPhongShader_litSphereTwoLights() throws {
    let mesh = try makeSphereMeshWithTangents()

    let projection = perspectiveProjection()
    let cameraMatrix = float4x4(translation: SIMD3<Float>(0, 0, 3))
    let viewMatrix = cameraMatrix.inverse
    let modelMatrix = matrix_identity_float4x4

    let lighting = try Lighting(
        ambientLightColor: [0.05, 0.05, 0.1],
        lights: [
            ([3, 2, 2], Light(type: .point, color: [1, 0.9, 0.7], intensity: 12)),
            ([-3, -1, 2], Light(type: .point, color: [0.3, 0.4, 1], intensity: 10))
        ]
    )

    let material = BlinnPhongMaterial(
        ambient: .color([0.05, 0.05, 0.05]),
        diffuse: .color([0.4, 0.4, 0.45]),
        specular: .color([0.9, 0.9, 0.9]),
        shininess: 64
    )

    let renderPass = try RenderPass {
        try BlinnPhongShader {
            try Draw(mesh: mesh)
            .vertexBuffers(of: mesh)
            .blinnPhongMaterial(material)
            .blinnPhongMatrices(
                projectionMatrix: projection,
                viewMatrix: viewMatrix,
                modelMatrix: modelMatrix,
                cameraMatrix: cameraMatrix
            )
            .lighting(lighting)
        }
        .vertexDescriptor(mesh.vertexDescriptor)
        .depthCompare(function: .less, enabled: true)
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.fractionOfBlackPixels() < 0.95)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "BlinnPhongSphereTwoLights"))
}
