// End-to-end test for RayTracedShadowComputePass.
//
// Renders a sphere with FlatShader (to get scene depth + color), then runs the
// RT shadow compute pass to overwrite shadowed pixels in the color texture.
//
// Skips automatically on devices that do not support ray tracing.

import CoreGraphics
import Foundation
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

@Test(.requiresMetal4, .disabled(if: !supportsRaytracing, "Ray tracing unsupported on this GPU — see issue #29"))
@MainActor
func testRayTracedShadowComputePass_endToEnd() throws {
    let device = _MTLCreateSystemDefaultDevice()
    try #require(device.supportsRaytracing, "Ray tracing not supported on this device")

    // Scene: a sphere floating above a ground plane, lit from above.
    // The sphere should cast a visible shadow onto the plane.
    let scene = try ShadowTestScene()

    // Single point light above the scene, off to one side so the shadow falls
    // onto the plane visibly.
    let lighting = try Lighting(
        ambientLightColor: [0.15, 0.15, 0.2],
        lights: [
            (scene.lightPosition, Light(type: .point, color: [1, 1, 1], intensity: 30))
        ]
    )

    // The technique builds the acceleration structures (sphere + plane, one instance each) and
    // owns their lifetime.
    let technique = try RayTracedShadowTechnique(
        meshes: [scene.sphere, scene.plane],
        instances: [
            AccelerationStructureManager.Instance(meshIndex: 0, transform: scene.sphereTransform),
            AccelerationStructureManager.Instance(meshIndex: 1, transform: scene.planeTransform)
        ],
        lighting: lighting
    )

    let context = try ShadowContext(
        viewTransforms: scene.viewTransforms,
        colorTexture: scene.renderer.colorTexture,
        depthTexture: scene.renderer.depthTexture
    )

    // Same wiring as the shadow-mapped technique: the technique decides which passes run and when.
    let combined = try ShadowedScene(technique: technique, context: context) {
        try scene.scenePass
    }

    let rendering = try scene.renderer.render(combined)
    let image = try rendering.cgImage
    #expect(try image.isEqualToGoldenImage(named: "RayTracedShadowSphere"))
}

// MARK: - Light types (#93)

@MainActor
private func renderRayTracedShadows(scene: ShadowTestScene, lighting: Lighting) throws -> CGImage {
    let technique = try RayTracedShadowTechnique(
        meshes: [scene.sphere, scene.plane],
        instances: [
            AccelerationStructureManager.Instance(meshIndex: 0, transform: scene.sphereTransform),
            AccelerationStructureManager.Instance(meshIndex: 1, transform: scene.planeTransform)
        ],
        lighting: lighting
    )
    let context = try ShadowContext(viewTransforms: scene.viewTransforms, colorTexture: scene.renderer.colorTexture, depthTexture: scene.renderer.depthTexture)
    let combined = try ShadowedScene(technique: technique, context: context) {
        try scene.scenePass
    }
    return try scene.renderer.render(combined).cgImage
}

@MainActor
private func shadowContrast(scene: ShadowTestScene, image: CGImage) throws -> Double {
    let shadow = scene.pixelPosition(of: scene.groundShadowCentre)
    let lit = scene.pixelPosition(of: scene.groundLitPoint)
    return try image.luminance(atX: lit.x, y: lit.y) - image.luminance(atX: shadow.x, y: shadow.y)
}

@Test(.requiresMetal4, .disabled(if: !supportsRaytracing, "Ray tracing unsupported on this GPU — see issue #29"))
@MainActor
func testRayTracedShadows_directionalLightUsesDirectionNotPosition() throws {
    let scene = try ShadowTestScene()
    // Position is below the floor; only the direction (toward the origin from `lightPosition`) should matter.
    let lighting = try Lighting(
        ambientLightColor: [0, 0, 0],
        orientedLights: [(position: [0, -10, 0], direction: -scene.lightPosition, light: Light(type: .directional, intensity: 1))]
    )
    let image = try renderRayTracedShadows(scene: scene, lighting: lighting)
    #expect(try shadowContrast(scene: scene, image: image) > 0.1)
}

@Test(.requiresMetal4, .disabled(if: !supportsRaytracing, "Ray tracing unsupported on this GPU — see issue #29"))
@MainActor
func testRayTracedShadows_spotLightOutsideConeCastsNoShadow() throws {
    let scene = try ShadowTestScene()
    // Same place as the point light in the end-to-end test, but pointing up, away from the scene.
    let lighting = try Lighting(
        ambientLightColor: [0, 0, 0],
        orientedLights: [(position: scene.lightPosition, direction: [0, 1, 0], light: Light.spot(intensity: 30))]
    )
    let image = try renderRayTracedShadows(scene: scene, lighting: lighting)
    #expect(abs(try shadowContrast(scene: scene, image: image)) < 0.02)
}
