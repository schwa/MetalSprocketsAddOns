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

// MARK: - Self-shadow terminator (#58)

/// Compares the sphere's self-shadow against the smooth sphere: a pixel should be dark exactly where the true sphere
/// normal faces away from the light. Only pixels near the terminator are compared, where the triangles' steps show;
/// pixels within `margin` of it are skipped, as the tessellated surface differs a little from the true sphere there.
/// Returns the number of disagreeing pixels and the number compared.
@MainActor
func sphereTerminatorMismatches(scene: ShadowTestScene, image: CGImage, lightDirection: SIMD3<Float>? = nil, margin: Float = 0.02, band: Float = 0.2) -> (mismatches: Int, compared: Int) {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    let inverse = scene.inverseViewProjection
    let centre = scene.sphereTransform.translation
    // MDLMesh's sphere extent is its radius.
    let radius = scene.sphereExtent.x
    var mismatches = 0
    var compared = 0
    for y in 0..<height {
        for x in 0..<width {
            let ndc = SIMD2<Float>((Float(x) + 0.5) / Float(width) * 2 - 1, 1 - (Float(y) + 0.5) / Float(height) * 2)
            let near = inverse * SIMD4<Float>(ndc.x, ndc.y, 0, 1)
            let far = inverse * SIMD4<Float>(ndc.x, ndc.y, 1, 1)
            let origin = SIMD3<Float>(near.x, near.y, near.z) / near.w
            let direction = normalize(SIMD3<Float>(far.x, far.y, far.z) / far.w - origin)
            // Ray-sphere intersection, nearest hit.
            let offset = origin - centre
            let b = dot(offset, direction)
            let discriminant = b * b - (dot(offset, offset) - radius * radius)
            guard discriminant > 0 else {
                continue
            }
            let point = origin + direction * (-b - discriminant.squareRoot())
            let facing = dot(normalize(point - centre), lightDirection ?? normalize(scene.lightPosition - point))
            guard abs(facing) > margin, abs(facing) < band else {
                continue
            }
            let index = (y * width + x) * 4
            let luminance = (0.2126 * Float(pixels[index]) + 0.7152 * Float(pixels[index + 1]) + 0.0722 * Float(pixels[index + 2])) / 255
            let dark = luminance < 0.3
            compared += 1
            if dark != (facing < 0) {
                mismatches += 1
            }
        }
    }
    return (mismatches, compared)
}

@Test(.requiresMetal4, .disabled(if: !supportsRaytracing, "Ray tracing unsupported on this GPU — see issue #29"))
@MainActor
func testRayTracedShadows_smoothNormalsGiveSmoothTerminator() throws {
    let scene = try ShadowTestScene()
    let lighting = try Lighting(ambientLightColor: [0, 0, 0], lights: [(scene.lightPosition, Light(type: .point, color: [1, 1, 1], intensity: 30))])
    let image = try renderRayTracedShadows(scene: scene, lighting: lighting, normalTexture: try scene.renderNormals())
    let result = sphereTerminatorMismatches(scene: scene, image: image)
    #expect(result.compared > 500)
    #expect(result.mismatches * 100 < result.compared, "\(result.mismatches) of \(result.compared) sphere pixels disagree with the smooth terminator")
}

// MARK: - Light types (#93)

@MainActor
private func renderRayTracedShadows(scene: ShadowTestScene, lighting: Lighting, normalTexture: MTLTexture? = nil) throws -> CGImage {
    let technique = try RayTracedShadowTechnique(
        meshes: [scene.sphere, scene.plane],
        instances: [
            AccelerationStructureManager.Instance(meshIndex: 0, transform: scene.sphereTransform),
            AccelerationStructureManager.Instance(meshIndex: 1, transform: scene.planeTransform)
        ],
        lighting: lighting
    )
    let context = try ShadowContext(viewTransforms: scene.viewTransforms, colorTexture: scene.renderer.colorTexture, depthTexture: scene.renderer.depthTexture, normalTexture: normalTexture)
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
