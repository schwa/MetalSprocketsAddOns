// Runtime GPU capability checks used to gate tests that need hardware features the current device may not have
// (see issue #29). The device checks live in MetalSupport; this file wraps them for Swift Testing.

import CoreGraphics
import Metal
import MetalSprockets
@testable import MetalSprocketsAddOns
import MetalSupport
import simd
import Testing

private let device = MTLCreateSystemDefaultDevice()

/// True when the current default device can encode mesh-shader draws.
let supportsMeshShaders: Bool = device?.supportsMeshShaders ?? false

/// True when the current default device supports ray tracing.
let supportsRaytracing: Bool = device?.supportsRaytracing ?? false

/// True when the current default device supports Metal 4. MetalSprockets renders only with Metal 4.
///
/// The GitHub Actions runner's paravirtual GPU has no Metal 4 support (see issue #44).
let supportsMetal4: Bool = device?.supportsMetal4 ?? false

extension Trait where Self == ConditionTrait {
    /// Skips a test that renders through MetalSprockets on a GPU without Metal 4.
    static var requiresMetal4: Self {
        .disabled(if: !supportsMetal4, "Needs a Metal 4 GPU — see issue #44")
    }
}

/// True when the current default device samples textures correctly.
///
/// The GitHub Actions runner's paravirtual GPU returns a constant instead of texel data —
/// plain `rgba8Unorm` samples as white — so every golden image that samples a texture is
/// wrong there (see issue #44). Sample a known solid-blue texture and check the result is
/// actually blue.
///
/// A probe that fails for any other reason reports support, so the affected tests run and
/// report the real error rather than silently disappearing.
let supportsTextureSampling: Bool = {
    do {
        let device = _MTLCreateSystemDefaultDevice()
        let texture = try makeSolidColorTexture(device: device, size: 4, color: [0, 0, 255, 255])
        let renderer = try OffscreenRenderer(size: CGSize(width: 32, height: 32))
        let rendering = try renderer.render(try RenderPass {
            try TextureBillboardPipeline(specifier: ColorSource.texture2D(texture))
        })
        let pixel = try rendering.cgImage.pixel(atX: 16, y: 16)
        return pixel.z > 200 && pixel.x < 64
    } catch {
        print("Texture sampling probe failed, assuming sampling works: \(error)")
        return true
    }
}()
