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

    // Build acceleration structures: two meshes (sphere + plane), two instances.
    var accelManager = try AccelerationStructureManager()
    try accelManager.build(meshes: [scene.sphere, scene.plane], instances: [
        AccelerationStructureManager.Instance(meshIndex: 0, transform: scene.sphereTransform),
        AccelerationStructureManager.Instance(meshIndex: 1, transform: scene.planeTransform)
    ])

    // Single point light above the scene, off to one side so the shadow falls
    // onto the plane visibly.
    let lighting = try Lighting(
        ambientLightColor: [0.15, 0.15, 0.2],
        lights: [
            (scene.lightPosition, Light(type: .point, color: [1, 1, 1], intensity: 30))
        ]
    )

    // OffscreenRenderer.render(_:) already wraps content in a CommandBufferElement,
    // so we just need a Group containing the scene render passes + the RT compute pass.
    let combined = try MetalSprockets.Group {
        // 1. Render the sphere + plane with FlatShader (populates color + depth).
        try scene.scenePass

        // 2. RT shadow compute pass: darkens shadowed pixels in the color texture.
        try RayTracedShadowComputePass(
            sceneDepthTexture: scene.renderer.depthTexture,
            outputTexture: scene.renderer.colorTexture,
            accelerationStructureManager: accelManager,
            lighting: lighting,
            inverseViewProjection: scene.inverseViewProjection,
            shadowIntensity: 1.0
        )
    }

    let rendering = try scene.renderer.render(combined)
    let image = try rendering.cgImage
    #expect(try image.isEqualToGoldenImage(named: "RayTracedShadowSphere"))
}
