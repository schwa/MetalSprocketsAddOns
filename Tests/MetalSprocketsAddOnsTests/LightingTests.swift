// Direct unit tests for `Light` (init convenience) and `Lighting` (init / mutators / argument buffer).

import Metal
@testable import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import MetalSupport
import simd
import Testing

// MARK: - Light convenience init

@Test
func testLight_convenienceInit_defaultColorAndIntensity() {
    let light = Light(type: .point)
    #expect(light.type == .point)
    #expect(light.color == SIMD3<Float>(1, 1, 1))
    #expect(light.intensity == 1.0)
    #expect(light.range == .infinity)
}

@Test
func testLight_convenienceInit_customColorAndIntensity() {
    let light = Light(type: .directional, color: [0.5, 0.7, 0.9], intensity: 5.0)
    #expect(light.type == .directional)
    #expect(light.color == SIMD3<Float>(0.5, 0.7, 0.9))
    #expect(light.intensity == 5.0)
    #expect(light.range == .infinity)
}

// MARK: - Lighting.init

@Test
@MainActor
func testLighting_init_singleLight() throws {
    let lighting = try Lighting(
        ambientLightColor: [0.1, 0.2, 0.3],
        lights: [
            ([1, 2, 3], Light(type: .point, color: [1, 0, 0], intensity: 8))
        ]
    )

    #expect(lighting.count == 1)
    #expect(lighting.ambientLightColor == SIMD3<Float>(0.1, 0.2, 0.3))
    #expect(lighting.lights.length >= MemoryLayout<Light>.stride)
    #expect(lighting.lightPositions.length >= MemoryLayout<SIMD3<Float>>.stride)
}

@Test
@MainActor
func testLighting_init_multipleLights() throws {
    let lighting = try Lighting(
        ambientLightColor: [0, 0, 0],
        lights: [
            ([0, 0, 0], Light(type: .point, intensity: 1)),
            ([1, 1, 1], Light(type: .directional, intensity: 2)),
            ([-1, -1, -1], Light(type: .point, intensity: 3))
        ]
    )

    #expect(lighting.count == 3)
}

// MARK: - setLightPosition / setLight

@Test
@MainActor
func testLighting_setLightPosition_updatesBuffer() throws {
    let lighting = try Lighting(
        ambientLightColor: [0, 0, 0],
        lights: [
            ([1, 2, 3], Light(type: .point, intensity: 1)),
            ([4, 5, 6], Light(type: .point, intensity: 2))
        ]
    )

    lighting.setLightPosition([10, 20, 30], at: 0)
    lighting.setLightPosition([40, 50, 60], at: 1)

    let positions = lighting.lightPositions.contents()
        .assumingMemoryBound(to: SIMD3<Float>.self)
    #expect(positions[0] == SIMD3<Float>(10, 20, 30))
    #expect(positions[1] == SIMD3<Float>(40, 50, 60))
}

@Test
@MainActor
func testLighting_setLight_updatesBuffer() throws {
    let lighting = try Lighting(
        ambientLightColor: [0, 0, 0],
        lights: [
            ([0, 0, 0], Light(type: .point, color: [1, 0, 0], intensity: 1)),
            ([0, 0, 0], Light(type: .point, color: [0, 1, 0], intensity: 1))
        ]
    )

    let updated = Light(type: .directional, color: [0, 0, 1], intensity: 5)
    lighting.setLight(updated, at: 0)

    let lights = lighting.lights.contents()
        .assumingMemoryBound(to: Light.self)
    #expect(lights[0].type == .directional)
    #expect(lights[0].color == SIMD3<Float>(0, 0, 1))
    #expect(lights[0].intensity == 5)
}

// MARK: - toArgumentBuffer

@Test
@MainActor
func testLighting_toArgumentBuffer_capturesCountAndAmbient() throws {
    let lighting = try Lighting(
        ambientLightColor: [0.4, 0.5, 0.6],
        lights: [
            ([0, 0, 0], Light(type: .point, intensity: 1)),
            ([1, 1, 1], Light(type: .point, intensity: 1))
        ]
    )

    let argBuffer = try lighting.toArgumentBuffer()
    #expect(argBuffer.lightCount == 2)
    #expect(argBuffer.ambientLightColor == SIMD3<Float>(0.4, 0.5, 0.6))
}
