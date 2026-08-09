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

@Test(.disabled(if: !supportsRaytracing, "Ray tracing unsupported on this GPU — see issue #29"))
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
