// Runtime GPU capability probes used to gate tests that need hardware features
// the current device may not have (see issue #29).

import CoreGraphics
import Metal
import MetalSprockets
@testable import MetalSprocketsAddOns
import MetalSupport
import simd

/// True when the current default device can encode mesh-shader draws.
///
/// Paravirtualized GPUs (GitHub Actions runners, VMs) advertise a Metal 3 device
/// but their render command encoder does not implement the mesh-stage selectors,
/// so binding a mesh buffer raises `NSInvalidArgumentException` and kills the
/// test process.
///
/// Probing `respondsToSelector` on an encoder is not enough on its own: when a
/// validation or debug layer wraps the encoder, the wrapper answers for every
/// protocol selector and forwards to the real encoder, which then dies on the
/// selector anyway. GitHub Actions hit exactly that — the probe reported mesh
/// support and `testGraphicsContext3D_debugWireframe` crashed the test process.
/// So paravirtual devices are excluded by name first.
let supportsMeshShaders: Bool = {
    guard let device = MTLCreateSystemDefaultDevice(), let commandQueue = device.makeCommandQueue() else {
        return false
    }
    guard !device.isParavirtual else {
        return false
    }
    let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
    textureDescriptor.usage = [.renderTarget]
    textureDescriptor.storageMode = .private
    guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
        return false
    }
    let renderPassDescriptor = MTLRenderPassDescriptor()
    renderPassDescriptor.colorAttachments[0].texture = texture
    renderPassDescriptor.colorAttachments[0].loadAction = .clear
    renderPassDescriptor.colorAttachments[0].storeAction = .dontCare
    guard let commandBuffer = commandQueue.makeCommandBuffer(),
          let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
        return false
    }
    let responds = (encoder as AnyObject).responds(to: NSSelectorFromString("setMeshBuffer:offset:atIndex:"))
    encoder.endEncoding()
    return responds
}()

/// True when the current default device supports ray tracing.
let supportsRaytracing: Bool = MTLCreateSystemDefaultDevice()?.supportsRaytracing ?? false

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

extension MTLDevice {
    /// True for the paravirtualized GPU exposed inside macOS VMs, including CI runners.
    var isParavirtual: Bool {
        name.localizedCaseInsensitiveContains("paravirtual")
    }
}
