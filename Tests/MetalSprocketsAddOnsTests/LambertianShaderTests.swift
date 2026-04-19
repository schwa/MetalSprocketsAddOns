// LambertianShader golden-image tests.

import CoreGraphics
import GeometryLite3D
import Metal
import MetalKit
import MetalSprockets
@testable import MetalSprocketsAddOns
import MetalSprocketsSupport
import MetalSupport
import simd
import Testing

@Test
@MainActor
func testLambertianShader_litSphere() throws {
    let mesh = MTKMesh.sphere(extent: [1, 1, 1])

    let projection = perspectiveProjection()
    let camera = float4x4(translation: SIMD3<Float>(0, 0, 3))
    let model = matrix_identity_float4x4

    let renderPass = try RenderPass {
        LambertianShader(
            projectionMatrix: projection,
            cameraMatrix: camera,
            modelMatrix: model,
            color: [0.7, 0.3, 0.2],
            lightDirection: simd_normalize(SIMD3<Float>(0.5, 0.7, 0.5))
        ) {
            Draw { encoder in
                encoder.setVertexBuffers(of: mesh)
                encoder.draw(mesh)
            }
        }
        .vertexDescriptor(MTLVertexDescriptor(mesh.vertexDescriptor))
        .depthCompare(function: .less, enabled: true)
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "LambertianSphere"))
}

@Test
@MainActor
func testLambertianShader_litBox() throws {
    let mesh = MTKMesh.box(extent: [1, 1, 1])

    let projection = perspectiveProjection()
    let camera = float4x4(translation: SIMD3<Float>(0, 0, 3))
    let model = float4x4(simd_quatf(angle: .pi / 5, axis: simd_normalize(SIMD3<Float>(1, 1, 0))))

    let renderPass = try RenderPass {
        LambertianShader(
            projectionMatrix: projection,
            cameraMatrix: camera,
            modelMatrix: model,
            color: [0.2, 0.5, 0.8],
            lightDirection: simd_normalize(SIMD3<Float>(0.3, 0.6, 0.7))
        ) {
            Draw { encoder in
                encoder.setVertexBuffers(of: mesh)
                encoder.draw(mesh)
            }
        }
        .vertexDescriptor(MTLVertexDescriptor(mesh.vertexDescriptor))
        .depthCompare(function: .less, enabled: true)
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "LambertianBox"))
}

@Test
@MainActor
func testLambertianShaderInstanced_grid() throws {
    let mesh = MTKMesh.sphere(extent: [0.4, 0.4, 0.4])

    let projection = perspectiveProjection()
    let camera = float4x4(translation: SIMD3<Float>(0, 0, 5))

    var modelMatrices: [simd_float4x4] = []
    var colors: [SIMD3<Float>] = []
    for x in -1...1 {
        for y in -1...1 {
            modelMatrices.append(float4x4(translation: SIMD3<Float>(Float(x), Float(y), 0)))
            colors.append([Float(x + 1) / 2, Float(y + 1) / 2, 0.5])
        }
    }

    let renderPass = try RenderPass {
        LambertianShaderInstanced(
            projectionMatrix: projection,
            cameraMatrix: camera,
            colors: colors,
            modelMatrices: modelMatrices,
            lightDirection: simd_normalize(SIMD3<Float>(0.5, 0.5, 1))
        ) {
            Draw { encoder in
                encoder.setVertexBuffers(of: mesh)
                encoder.draw(mesh, instanceCount: modelMatrices.count)
            }
        }
        .vertexDescriptor(MTLVertexDescriptor(mesh.vertexDescriptor))
        .depthCompare(function: .less, enabled: true)
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "LambertianInstancedGrid"))
}
