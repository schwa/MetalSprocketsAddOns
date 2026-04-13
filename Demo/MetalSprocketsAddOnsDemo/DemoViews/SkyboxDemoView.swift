import DemoKit
import Interaction3D
import MetalKit
import MetalSprockets
import MetalSprocketsAddOns
import MetalSprocketsSupport
import MetalSprocketsUI
import SwiftUI

struct SkyboxDemoView: DemoView {
    static let metadata = DemoMetadata(
        name: "Skybox",
        systemImage: "cube.transparent",
        description: "Cubemap skybox rendered from a cross-layout texture",
        group: "Rendering"
    )

    @State private var cameraRotation = simd_quatf(angle: 0, axis: [0, 1, 0])
    @State private var cameraDistance: Float = 1
    @State private var cameraTarget: SIMD3<Float> = .zero

    @State private var skyboxTexture: MTLTexture?

    private var cameraMatrix: simd_float4x4 {
        let rotation = float4x4(cameraRotation)
        let translation = float4x4.translation(cameraTarget.x, cameraTarget.y, cameraTarget.z)
        let distance = float4x4.translation(0, 0, cameraDistance)
        return translation * rotation * distance
    }

    var body: some View {
        RenderView { _, drawableSize in
            let aspect = drawableSize.height > 0 ? Float(drawableSize.width / drawableSize.height) : 1.0
            let projectionMatrix = float4x4.perspective(fovY: .pi / 4, aspect: aspect, near: 0.1, far: 1_000.0)

            try RenderPass {
                if let skyboxTexture {
                    try SkyboxRenderPipeline(
                        projectionMatrix: projectionMatrix,
                        cameraMatrix: cameraMatrix,
                        rotation: simd_quatf(angle: .pi, axis: [0, 1, 0]),
                        texture: skyboxTexture
                    )
                }
            }
        }
        .metalDepthStencilPixelFormat(.depth32Float)
        .interactiveCamera(rotation: $cameraRotation, distance: $cameraDistance, target: $cameraTarget)
        .frameTimingOverlay()
        .task {
            do {
                let device = _MTLCreateSystemDefaultDevice()
                let crossTexture = try device.makeTexture(name: "Skybox", bundle: .main)
                skyboxTexture = try device.makeTextureCubeFromCrossTexture(texture: crossTexture)
            } catch {
                fatalError("Failed to load skybox texture: \(error)")
            }
        }
    }
}

#Preview {
    SkyboxDemoView()
}
