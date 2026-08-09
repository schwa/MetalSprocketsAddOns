// Runtime GPU capability probes used to gate tests that need hardware features
// the current device may not have (see issue #29).

import Metal
import MetalSupport

/// True when the current default device can encode mesh-shader draws.
///
/// Paravirtualized GPUs (GitHub Actions runners, VMs) advertise a Metal 3 device
/// but their render command encoder does not implement the mesh-stage selectors,
/// so binding a mesh buffer raises `NSInvalidArgumentException` and kills the
/// test process. Probing the encoder is the only reliable signal.
let supportsMeshShaders: Bool = {
    guard let device = MTLCreateSystemDefaultDevice(), let commandQueue = device.makeCommandQueue() else {
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
