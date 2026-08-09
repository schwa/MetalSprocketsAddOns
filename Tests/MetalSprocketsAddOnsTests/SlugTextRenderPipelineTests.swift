// SlugTextRenderPipeline golden-image tests.

import CoreGraphics
import CoreText
import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
@testable import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import MetalSupport
import simd
import Testing

@MainActor
private func attributedHello() -> NSAttributedString {
    // Text is laid out in pixels, so the point size scales with the render size to keep the
    // glyphs the same fraction of the golden image (and comfortably above sub-pixel detail).
    let pointSize = defaultRenderSize.height / 4
    let font = CTFontCreateWithName("Helvetica" as CFString, pointSize, nil)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    ]
    return NSAttributedString(string: "Hi", attributes: attrs)
}

/// Build an orthographic view-projection that maps text coordinates (px, with origin
/// at the top-left of the text mesh) to clip space for an N×N viewport.
private func textViewProjection(viewportSize: SIMD2<Float>, textBounds: CGRect) -> simd_float4x4 {
    // Slug text mesh y-axis points up (CoreText baseline). Translate so the text
    // is centered, then orthographically project.
    let cx = Float(textBounds.midX)
    let cy = Float(textBounds.midY)
    let halfW = viewportSize.x * 0.5
    let halfH = viewportSize.y * 0.5
    // Map world (cx ± halfW, cy ± halfH) → clip (−1, 1)
    let scaleX = 1.0 / halfW
    let scaleY = 1.0 / halfH
    let translate = float4x4(translation: SIMD3<Float>(-cx, -cy, 0))
    let scale = float4x4(diagonal: SIMD4<Float>(scaleX, scaleY, 1, 1))
    return scale * translate
}

@Test
@MainActor
func testSlugTextRenderPipeline_helloHelvetica() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let builder = SlugTextMeshBuilder(device: device)
    _ = builder.buildMesh(attributedString: attributedHello())
    let scene = try builder.finalize()

    let viewport = SIMD2<Float>(Float(defaultRenderSize.width), Float(defaultRenderSize.height))
    let vp = textViewProjection(viewportSize: viewport, textBounds: scene.meshes[0].bounds)
    let frame = SlugFrameConstants(viewProjectionMatrix: vp, viewportSize: viewport)

    let renderPass = try RenderPass {
        try SlugTextRenderPipeline(scene: scene, frameConstants: frame)
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "SlugTextHelloHelvetica"))
}

@Test
@MainActor
func testSlugTextRenderPipeline_usesSceneDevice() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let builder = SlugTextMeshBuilder(device: device)
    _ = builder.buildMesh(attributedString: attributedHello())
    let scene = try builder.finalize()

    let viewport = SIMD2<Float>(64, 64)
    let frame = SlugFrameConstants(viewProjectionMatrix: .identity, viewportSize: viewport)
    let pipeline = try SlugTextRenderPipeline(scene: scene, frameConstants: frame)

    // The pipeline must allocate from the device that owns the scene's resources rather than
    // reaching for the system default device.
    #expect(pipeline.fontTextureBuffer.device === scene.device)
    #expect(scene.device === device)
    #expect(pipeline.fontTextureBuffer.length == scene.fontTexturePairs.count * 16)
}

@Test
@MainActor
func testSlugTextRenderPipeline_wireframe() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let builder = SlugTextMeshBuilder(device: device)
    _ = builder.buildMesh(attributedString: attributedHello())
    let scene = try builder.finalize()

    let viewport = SIMD2<Float>(Float(defaultRenderSize.width), Float(defaultRenderSize.height))
    let vp = textViewProjection(viewportSize: viewport, textBounds: scene.meshes[0].bounds)
    let frame = SlugFrameConstants(viewProjectionMatrix: vp, viewportSize: viewport)

    let renderPass = try RenderPass {
        try SlugTextRenderPipeline(scene: scene, frameConstants: frame, wireframe: true)
    }

    let renderer = try OffscreenRenderer(size: defaultRenderSize)
    let rendering = try renderer.render(renderPass)
    #expect(try rendering.cgImage.isEqualToGoldenImage(named: "SlugTextHelloWireframe"))
}
