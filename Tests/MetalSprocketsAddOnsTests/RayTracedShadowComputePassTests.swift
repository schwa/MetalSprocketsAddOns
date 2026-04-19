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

    // Scene: a single sphere at origin, lit from one point above it.
    let mesh = MTKMesh.sphere(extent: [1, 1, 1])
    let modelMatrix = matrix_identity_float4x4

    // Camera looking at origin from +Z.
    let camera = float4x4(translation: SIMD3<Float>(0, 0, 4))
    let projection = perspectiveProjection()
    let viewMatrix = camera.inverse
    let viewProjection = projection * viewMatrix
    let inverseVP = viewProjection.inverse

    // Build acceleration structures with the sphere as the single shadow caster.
    var accelManager = try AccelerationStructureManager()
    try accelManager.build(meshes: [mesh], instances: [
        AccelerationStructureManager.Instance(meshIndex: 0, transform: modelMatrix)
    ])

    // Single point light positioned above + slightly offset.
    let lighting = try Lighting(
        ambientLightColor: [0.1, 0.1, 0.1],
        lights: [
            ([2, 4, 2], Light(type: .point, color: [1, 1, 1], intensity: 10))
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
    // so we just need a Group containing the scene render pass + the RT compute pass.
    let combined = try MetalSprockets.Group {
        // 1. Render the sphere with FlatShader to populate color + depth.
        try RenderPass {
            try FlatShader(
                modelViewProjection: viewProjection,
                textureSpecifier: ColorSource.color([0.6, 0.6, 0.7])
            ) {
                Draw { encoder in
                    encoder.setVertexBuffers(of: mesh)
                    encoder.draw(mesh)
                }
            }
            .vertexDescriptor(MTLVertexDescriptor(mesh.vertexDescriptor))
            .depthCompare(function: .less, enabled: true)
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
