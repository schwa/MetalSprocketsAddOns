import CoreGraphics
import GeometryLite3D
import Metal
import MetalKit
import MetalSprockets
@testable import MetalSprocketsAddOns
import MetalSprocketsSupport
import MetalSupport
import simd

/// The scene shared by the shadow tests: a sphere floating above a ground plane, viewed from a
/// slight downward angle and lit by a single light up and to one side, so the sphere casts a
/// visible shadow onto the plane.
///
/// Both the shadow map and ray-traced shadow tests render this scene, so their golden images and
/// luminance expectations depend on the transforms here staying fixed.
@MainActor
struct ShadowTestScene {
    let sphere: MTKMesh
    let plane: MTKMesh
    let sphereTransform: float4x4
    let planeTransform: float4x4
    let viewTransforms: ViewTransforms
    let renderer: OffscreenRenderer

    /// World-space position of the single shadow-casting light.
    let lightPosition = SIMD3<Float>(3, 5, 2)

    init() throws {
        sphere = MTKMesh.sphere(extent: [0.6, 0.6, 0.6])
        plane = MTKMesh.plane(width: 4, height: 4)
        sphereTransform = float4x4(translation: SIMD3<Float>(0, 0.5, 0))
        // MTKMesh.plane lies in the XY plane; rotate it onto XZ (facing +Y) to make a floor.
        planeTransform = float4x4(translation: SIMD3<Float>(0, -1.0, 0))
            * float4x4(simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0)))

        let camera = float4x4(translation: SIMD3<Float>(0, 1.5, 4))
            * float4x4(simd_quatf(angle: -.pi / 8, axis: SIMD3<Float>(1, 0, 0)))
        viewTransforms = ViewTransforms(projectionMatrix: perspectiveProjection(), cameraMatrix: camera)

        // Shadow passes sample the scene depth texture and write the colour texture from compute,
        // so both attachments need wider usage than the offscreen renderer's defaults.
        renderer = try OffscreenRenderer(
            size: defaultRenderSize,
            colorUsage: [.renderTarget, .shaderRead, .shaderWrite],
            depthUsage: [.renderTarget, .shaderRead]
        )
    }

    var viewProjection: float4x4 {
        viewTransforms.viewProjectionMatrix
    }

    /// World-space point on the ground plane at the centre of the sphere's cast shadow.
    var groundShadowCentre: SIMD3<Float> {
        let direction = normalize(-lightPosition)
        let sphereCentre = sphereTransform.translation
        let distance = (planeTransform.translation.y - sphereCentre.y) / direction.y
        return sphereCentre + direction * distance
    }

    /// World-space point on the ground plane well clear of the cast shadow and of the sphere.
    var groundLitPoint: SIMD3<Float> {
        SIMD3<Float>(1.2, planeTransform.translation.y, 0.4)
    }

    /// The pixel a world-space point projects to, with the origin at the top-left of the render.
    func pixelPosition(of worldPoint: SIMD3<Float>) -> (x: Int, y: Int) {
        let clip = viewProjection * SIMD4<Float>(worldPoint, 1)
        let ndc = SIMD2<Float>(clip.x, clip.y) / clip.w
        let x = (ndc.x + 1) / 2 * Float(defaultRenderSize.width)
        let y = (1 - ndc.y) / 2 * Float(defaultRenderSize.height)
        return (Int(x), Int(y))
    }

    var inverseViewProjection: float4x4 {
        viewTransforms.inverseViewProjectionMatrix
    }

    /// Draws both meshes with `FlatShader`, populating the renderer's colour and depth textures.
    var scenePass: some Element {
        get throws {
            let viewProjection = viewProjection
            let sphere = sphere
            let plane = plane
            let sphereTransform = sphereTransform
            let planeTransform = planeTransform
            return try RenderPass {
                try MetalSprockets.Group {
                    try FlatShader(
                        modelViewProjection: viewProjection * sphereTransform,
                        textureSpecifier: ColorSource.color([0.8, 0.6, 0.4])
                    ) {
                        Draw(mesh: sphere)
                        .vertexBuffers(of: sphere)
                    }
                    .vertexDescriptor(MTLVertexDescriptor(sphere.vertexDescriptor))
                    .depthCompare(function: .less, enabled: true)

                    try FlatShader(
                        modelViewProjection: viewProjection * planeTransform,
                        textureSpecifier: ColorSource.color([0.8, 0.8, 0.85])
                    ) {
                        Draw(mesh: plane)
                        .vertexBuffers(of: plane)
                    }
                    .vertexDescriptor(MTLVertexDescriptor(plane.vertexDescriptor))
                    .depthCompare(function: .less, enabled: true)
                }
            }
        }
    }
}
