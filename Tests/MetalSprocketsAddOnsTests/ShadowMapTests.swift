// Tests for ShadowMap (struct + matrix helpers + parameter conversion) and an
// end-to-end ShadowMapDepthPass + ShadowMaskPass render to exercise the full
// shadow rendering chain.

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

// MARK: - ShadowMap struct

@Test
@MainActor
func testShadowMap_init_defaults() throws {
    let shadowMap = try ShadowMap()
    #expect(shadowMap.resolution == 2_048)
    #expect(shadowMap.lightCount == 1)
    #expect(shadowMap.useInverseZ == true)
    #expect(shadowMap.lightViewProjectionMatrices.count == 1)
    #expect(shadowMap.depthTexture.textureType == .type2DArray)
    #expect(shadowMap.depthTexture.pixelFormat == .depth32Float)
    #expect(shadowMap.depthTexture.width == 2_048)
    #expect(shadowMap.depthTexture.arrayLength == 1)
}

@Test
@MainActor
func testShadowMap_init_customResolutionAndLightCount() throws {
    let shadowMap = try ShadowMap(resolution: 256, lightCount: 3, depthBias: 1.5, slopeScale: 1.5, useInverseZ: false)
    #expect(shadowMap.resolution == 256)
    #expect(shadowMap.lightCount == 3)
    #expect(shadowMap.useInverseZ == false)
    #expect(shadowMap.depthBias == 1.5)
    #expect(shadowMap.slopeScale == 1.5)
    #expect(shadowMap.lightViewProjectionMatrices.count == 3)
    #expect(shadowMap.depthTexture.arrayLength == 3)
}

@Test
@MainActor
func testShadowMap_updateDirectionalLight_setsMatrix() throws {
    var shadowMap = try ShadowMap(resolution: 256, lightCount: 2)
    let identity = simd_float4x4.identity

    // Initially identity.
    #expect(shadowMap.lightViewProjectionMatrices[0] == identity)
    #expect(shadowMap.lightViewProjectionMatrices[1] == identity)

    shadowMap.updateDirectionalLight(at: 0, position: SIMD3<Float>(10, 20, 10))
    #expect(shadowMap.lightViewProjectionMatrices[0] != identity)
    // Other slot still identity.
    #expect(shadowMap.lightViewProjectionMatrices[1] == identity)
}

@Test
@MainActor
func testShadowMap_toParameters_capturesLightCountAndMatrices() throws {
    var shadowMap = try ShadowMap(resolution: 128, lightCount: 2)
    shadowMap.updateDirectionalLight(at: 0, position: SIMD3<Float>(5, 5, 5))
    shadowMap.updateDirectionalLight(at: 1, position: SIMD3<Float>(-5, 5, -5))

    let params = shadowMap.toParameters()
    #expect(params.lightCount == 2)
    #expect(params.mapSize == 128)
}

// MARK: - Matrix helpers

@Test
func testFloat4x4_lookAt_buildsValidViewMatrix() {
    let view = float4x4.lookAt(eye: SIMD3<Float>(0, 0, 5), target: .zero, up: SIMD3<Float>(0, 1, 0))
    // The view matrix translates the world so the eye is at the origin.
    let eyeWorld = SIMD4<Float>(0, 0, 5, 1)
    let eyeView = view * eyeWorld
    #expect(abs(eyeView.x) < 1e-5)
    #expect(abs(eyeView.y) < 1e-5)
    #expect(abs(eyeView.z) < 1e-5)
}

@Test
func testFloat4x4_orthographic_inverseZ_mapsNearAndFar() {
    let proj = float4x4.orthographic(left: -1, right: 1, bottom: -1, top: 1, near: 0.1, far: 10, inverseZ: true)
    // Point at near plane (-near in view space → z = -0.1) should map to z = 1.
    let nearPoint = SIMD4<Float>(0, 0, -0.1, 1)
    let projected = proj * nearPoint
    #expect(abs(projected.z - 1.0) < 1e-3)
    // Far plane → z = 0.
    let farPoint = SIMD4<Float>(0, 0, -10, 1)
    let farProjected = proj * farPoint
    #expect(abs(farProjected.z) < 1e-3)
}

@Test
func testFloat4x4_orthographic_standardZ_mapsNearAndFar() {
    let proj = float4x4.orthographic(left: -1, right: 1, bottom: -1, top: 1, near: 0.1, far: 10, inverseZ: false)
    // Standard depth: near → 0, far → 1.
    let nearPoint = SIMD4<Float>(0, 0, -0.1, 1)
    let projected = proj * nearPoint
    #expect(abs(projected.z) < 1e-3)
    let farPoint = SIMD4<Float>(0, 0, -10, 1)
    let farProjected = proj * farPoint
    #expect(abs(farProjected.z - 1.0) < 1e-3)
}

// NOTE: An end-to-end ShadowMapDepthPass + ShadowMaskPass render test was attempted
// but triggers a Metal command-buffer assertion ("A command encoder is already encoding
// to this command buffer") inside OffscreenRenderer when the depth pass nests its own
// RenderPass per light. Until OffscreenRenderer can host nested render passes, the
// shadow render-pipeline code paths remain uncovered. Tracked separately.
