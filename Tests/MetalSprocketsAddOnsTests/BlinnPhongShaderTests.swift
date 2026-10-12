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

// MARK: - Light types (#91)

@MainActor
private func renderLitSphere(lighting: Lighting) throws -> CGImage {
    let mesh = try makeSphereMeshWithTangents()
    let material = BlinnPhongMaterial(ambient: .color([0, 0, 0]), diffuse: .color([0.8, 0.8, 0.8]), specular: .color([0, 0, 0]), shininess: 16)
    let renderPass = try RenderPass {
        try BlinnPhongShader {
            try Draw(mesh: mesh)
            .vertexBuffers(of: mesh)
            .blinnPhongMaterial(material)
            .blinnPhongMatrices(Transforms(projectionMatrix: perspectiveProjection(), cameraMatrix: float4x4(translation: [0, 0, 3])))
            .lighting(lighting)
        }
        .vertexDescriptor(mesh.vertexDescriptor)
        .depthCompare(function: .less, enabled: true)
    }
    return try OffscreenRenderer(size: defaultRenderSize).render(renderPass).cgImage
}

@Test(.requiresMetal4)
@MainActor
func testBlinnPhongShader_directionalLightUsesDirectionNotPosition() throws {
    // Position is behind the sphere; only the direction should matter.
    let towardCamera = try Lighting(ambientLightColor: [0, 0, 0], orientedLights: [(position: [0, 0, -10], direction: [0, 0, -1], light: Light(type: .directional, intensity: 1))])
    let awayFromCamera = try Lighting(ambientLightColor: [0, 0, 0], orientedLights: [(position: [0, 0, 10], direction: [0, 0, 1], light: Light(type: .directional, intensity: 1))])

    let lit = try renderLitSphere(lighting: towardCamera).meanLuminance()
    let unlit = try renderLitSphere(lighting: awayFromCamera).meanLuminance()
    #expect(lit > 0.05)
    #expect(unlit < lit * 0.05)
}

@Test(.requiresMetal4)
@MainActor
func testBlinnPhongShader_spotLightConeFalloff() throws {
    let aimed = try Lighting(ambientLightColor: [0, 0, 0], orientedLights: [(position: [0, 0, 3], direction: [0, 0, -1], light: Light.spot(intensity: 20, innerConeAngle: .pi / 32, outerConeAngle: .pi / 24))])
    let aimedAway = try Lighting(ambientLightColor: [0, 0, 0], orientedLights: [(position: [0, 0, 3], direction: [0, 1, 0], light: Light.spot(intensity: 20, innerConeAngle: .pi / 32, outerConeAngle: .pi / 24))])
    let point = try Lighting(ambientLightColor: [0, 0, 0], lights: [([0, 0, 3], Light(type: .point, intensity: 20))])

    let aimedLuminance = try renderLitSphere(lighting: aimed).meanLuminance()
    let awayLuminance = try renderLitSphere(lighting: aimedAway).meanLuminance()
    let pointLuminance = try renderLitSphere(lighting: point).meanLuminance()
    #expect(aimedLuminance > 0)
    #expect(awayLuminance == 0)
    // The cone cuts off part of what a point light would reach.
    #expect(aimedLuminance < pointLuminance)
}

// MARK: - Instancing (#92)

@Test(.requiresMetal4)
@MainActor
func testBlinnPhongShader_instancedMatchesSeparateDraws() throws {
    let mesh = try makeBoxMeshWithTangents()
    let viewTransforms = ViewTransforms(projectionMatrix: perspectiveProjection(), cameraMatrix: float4x4(translation: [0, 0, 6]))
    let modelMatrices = (-1...1).map { float4x4(translation: [Float($0) * 1.5, 0, 0]) * float4x4(simd_quatf(angle: .pi / 5, axis: simd_normalize(SIMD3<Float>(1, 1, 0)))) }
    let lighting = try Lighting(ambientLightColor: [0.1, 0.1, 0.1], lights: [([2, 2, 4], Light(type: .point, intensity: 20))])
    let material = BlinnPhongMaterial(ambient: .color([0.1, 0.1, 0.1]), diffuse: .color([0.7, 0.3, 0.2]), specular: .color([0.5, 0.5, 0.5]), shininess: 16)

    let instancedPass = try RenderPass {
        try BlinnPhongShader(instanced: true) {
            try Draw(mesh: mesh, instanceCount: modelMatrices.count)
            .vertexBuffers(of: mesh)
            .blinnPhongMaterial(material)
            .blinnPhongInstancedMatrices(viewTransforms, modelMatrices: modelMatrices)
            .lighting(lighting)
        }
        .vertexDescriptor(mesh.vertexDescriptor)
        .depthCompare(function: .less, enabled: true)
    }
    let separatePass = try RenderPass {
        try BlinnPhongShader {
            try ForEach(Array(modelMatrices.enumerated()), id: \.offset) { _, modelMatrix in
                try Draw(mesh: mesh)
                .vertexBuffers(of: mesh)
                .blinnPhongMaterial(material)
                .blinnPhongMatrices(viewTransforms.transforms(modelMatrix: modelMatrix))
                .lighting(lighting)
            }
        }
        .vertexDescriptor(mesh.vertexDescriptor)
        .depthCompare(function: .less, enabled: true)
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let instanced = try renderer.render(instancedPass).cgImage
    let separate = try renderer.render(separatePass).cgImage
    #expect(try instanced.fractionOfBlackPixels() < 0.95)
    #expect(abs(try instanced.meanLuminance() - separate.meanLuminance()) < 0.001)
}
