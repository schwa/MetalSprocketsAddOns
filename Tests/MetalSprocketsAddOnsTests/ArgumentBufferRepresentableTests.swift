// Tests that argument-buffer packing and the reported resource residency list stay in sync.

import Metal
@testable import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import MetalSupport
import simd
import Testing

// MARK: - ColorSource

@Test
@MainActor
func testColorSource_argumentBufferResources_coversEveryTextureCase() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let texture2D = try makeCheckerboardTexture(device: device, size: 4)
    let cube = try makeGradientCubeTexture(device: device, size: 4)
    let depth = try makeSolidColorTexture(device: device, size: 4, color: [1, 2, 3, 4])

    #expect(ColorSource.texture2D(texture2D, nil).argumentBufferResources.count == 1)
    #expect(ColorSource.texture2D(texture2D, nil).argumentBufferResources.first as? any MTLTexture === texture2D)
    #expect(ColorSource.textureCube(cube, nil, 0).argumentBufferResources.first as? any MTLTexture === cube)
    #expect(ColorSource.depth2D(depth, nil).argumentBufferResources.first as? any MTLTexture === depth)
    #expect(ColorSource.color([1, 0, 0]).argumentBufferResources.isEmpty)
}

// MARK: - BlinnPhongMaterial

@Test
@MainActor
func testBlinnPhongMaterial_argumentBufferResources_includesEverySlot() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let ambient = try makeCheckerboardTexture(device: device, size: 4)
    let diffuse = try makeGradientCubeTexture(device: device, size: 4)
    let specular = try makeSolidColorTexture(device: device, size: 4, color: [9, 9, 9, 255])

    let material = BlinnPhongMaterial(
        ambient: .texture2D(ambient, nil),
        diffuse: .textureCube(diffuse, nil, 0),
        specular: .depth2D(specular, nil),
        shininess: 8
    )

    let resources = material.argumentBufferResources.compactMap { $0 as? any MTLTexture }
    #expect(resources.count == 3)
    #expect(resources.contains { $0 === ambient })
    #expect(resources.contains { $0 === diffuse })
    #expect(resources.contains { $0 === specular })
}

@Test
@MainActor
func testBlinnPhongMaterial_argumentBufferResources_emptyForPlainColors() throws {
    let material = BlinnPhongMaterial(
        ambient: .color([0.1, 0.1, 0.1]),
        diffuse: .color([0.5, 0.5, 0.5]),
        specular: .color([1, 1, 1]),
        shininess: 8
    )
    #expect(material.argumentBufferResources.isEmpty)
}

// MARK: - Lighting

@Test
@MainActor
func testLighting_argumentBufferResources_areTheBuffersTheArgumentBufferPointsAt() throws {
    let lighting = try Lighting(
        ambientLightColor: [0, 0, 0],
        lights: [([0, 0, 1], Light(type: .point, intensity: 1))]
    )

    let buffers = lighting.argumentBufferResources.compactMap { $0 as? any MTLBuffer }
    #expect(buffers.count == 2)
    #expect(buffers.contains { $0 === lighting.lights })
    #expect(buffers.contains { $0 === lighting.lightPositions })
}
