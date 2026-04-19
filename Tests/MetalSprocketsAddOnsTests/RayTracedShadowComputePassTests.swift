// End-to-end test for RayTracedShadowComputePass.
//
// Renders a sphere with FlatShader (to get scene depth + color), then runs the
// RT shadow compute pass to overwrite shadowed pixels in the color texture.
//
// Skips automatically on devices that do not support ray tracing.

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

@Test
@MainActor
func testRayTracedShadowComputePass_endToEnd() throws {
    let device = _MTLCreateSystemDefaultDevice()
    try #require(device.supportsRaytracing, "Ray tracing not supported on this device")

    // Scene: a sphere floating above a ground plane, lit from above.
    // The sphere should cast a visible shadow onto the plane.
    let sphere = MTKMesh.sphere(extent: [0.6, 0.6, 0.6])
    let plane = MTKMesh.plane(width: 4, height: 4)

    // Sphere centered above origin, plane at y = -1.0 (well below sphere).
    let sphereTransform = float4x4(translation: SIMD3<Float>(0, 0.5, 0))
    let planeTransform = float4x4(translation: SIMD3<Float>(0, -1.0, 0))

    // Camera looking at the scene from a slight downward angle.
    let camera = float4x4(translation: SIMD3<Float>(0, 1.5, 4))
        * float4x4(simd_quatf(angle: -.pi / 8, axis: SIMD3<Float>(1, 0, 0)))
    let projection = perspectiveProjection()
    let viewMatrix = camera.inverse
    let viewProjection = projection * viewMatrix
    let inverseVP = viewProjection.inverse

    // Build acceleration structures: two meshes (sphere + plane), two instances.
    var accelManager = try AccelerationStructureManager()
    try accelManager.build(meshes: [sphere, plane], instances: [
        AccelerationStructureManager.Instance(meshIndex: 0, transform: sphereTransform),
        AccelerationStructureManager.Instance(meshIndex: 1, transform: planeTransform)
    ])

    // Single point light above the scene, off to one side so the shadow falls
    // onto the plane visibly.
    let lighting = try Lighting(
        ambientLightColor: [0.15, 0.15, 0.2],
        lights: [
            ([3, 5, 2], Light(type: .point, color: [1, 1, 1], intensity: 30))
        ]
    )

    // Renderer must produce textures usable for both shaderRead (depth) and
    // shaderWrite (compute output). The default OffscreenRenderer color texture
    // is BGRA8Unorm_sRGB with [.renderTarget, .shaderRead, .shaderWrite] which
    // works as the compute kernel's writable output.
    let renderer = try OffscreenRenderer(size: defaultRenderSize)

    // We can't write into the depth texture from compute, but we can sample it.
    // The default OffscreenRenderer depth texture is created with
    // [.renderTarget, .shaderRead] which is fine.

    // OffscreenRenderer.render(_:) already wraps content in a CommandBufferElement,
    // so we just need a Group containing the scene render passes + the RT compute pass.
    let combined = try MetalSprockets.Group {
        // 1. Render the sphere + plane with FlatShader (populates color + depth).
        try RenderPass {
            try MetalSprockets.Group {
                try FlatShader(
                    modelViewProjection: viewProjection * sphereTransform,
                    textureSpecifier: ColorSource.color([0.8, 0.6, 0.4])
                ) {
                    Draw { encoder in
                        encoder.setVertexBuffers(of: sphere)
                        encoder.draw(sphere)
                    }
                }
                .vertexDescriptor(MTLVertexDescriptor(sphere.vertexDescriptor))
                .depthCompare(function: .less, enabled: true)

                try FlatShader(
                    modelViewProjection: viewProjection * planeTransform,
                    textureSpecifier: ColorSource.color([0.8, 0.8, 0.85])
                ) {
                    Draw { encoder in
                        encoder.setVertexBuffers(of: plane)
                        encoder.draw(plane)
                    }
                }
                .vertexDescriptor(MTLVertexDescriptor(plane.vertexDescriptor))
                .depthCompare(function: .less, enabled: true)
            }
        }

        // 2. RT shadow compute pass: darkens shadowed pixels in the color texture.
        try RayTracedShadowComputePass(
            sceneDepthTexture: renderer.depthTexture,
            outputTexture: renderer.colorTexture,
            accelerationStructureManager: accelManager,
            lighting: lighting,
            inverseViewProjection: inverseVP,
            shadowIntensity: 1.0
        )
    }

    let rendering = try renderer.render(combined)
    let image = try rendering.cgImage
    #expect(try image.isEqualToGoldenImage(named: "RayTracedShadowSphere"))
}
