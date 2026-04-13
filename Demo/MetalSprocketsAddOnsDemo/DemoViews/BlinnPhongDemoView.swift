import DemoKit
import GeometryLite3D
import Interaction3D
import Metal
import MetalKit
import MetalSprockets
import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import MetalSprocketsUI
import simd
import SwiftUI

struct BlinnPhongDemoView: DemoView {
    static let metadata = DemoMetadata(
        name: "Blinn-Phong",
        systemImage: "light.max",
        description: "Blinn-Phong shading with multiple models, skybox, and grid",
        group: "Rendering"
    )

    @State private var cameraRotation = simd_quatf(angle: -.pi / 6, axis: [1, 0, 0])
    @State private var cameraDistance: Float = 10
    @State private var cameraTarget: SIMD3<Float> = [0, 1, 0]

    @State private var lighting: Lighting?
    @State private var skyboxTexture: MTLTexture?

    private var cameraMatrix: simd_float4x4 {
        let rotation = float4x4(cameraRotation)
        let translation = float4x4.translation(cameraTarget.x, cameraTarget.y, cameraTarget.z)
        let distance = float4x4.translation(0, 0, cameraDistance)
        return translation * rotation * distance
    }

    private let models: [Model] = [
        .init(
            id: "teapot-1",
            mesh: MTKMesh.teapot().relabeled("teapot"),
            modelMatrix: .init(translation: [-2.5, 0, 0]),
            material: BlinnPhongMaterial(
                ambient: .color([0.1, 0.05, 0.05]),
                diffuse: .color([0.6, 0.2, 0.2]),
                specular: .color([0.8, 0.8, 0.8]),
                shininess: 64
            )
        ),
        .init(
            id: "teapot-2",
            mesh: MTKMesh.teapot().relabeled("teapot"),
            modelMatrix: .init(translation: [2.5, 0, 0]),
            material: BlinnPhongMaterial(
                ambient: .color([0.05, 0.05, 0.1]),
                diffuse: .color([0.2, 0.2, 0.6]),
                specular: .color([0.8, 0.8, 0.8]),
                shininess: 64
            )
        ),
        .init(
            id: "floor-1",
            mesh: MTKMesh.plane(width: 10, height: 10),
            modelMatrix: .init(xRotation: .degrees(270)),
            material: BlinnPhongMaterial(
                ambient: .color([0.1, 0.1, 0.1]),
                diffuse: .color([0.4, 0.4, 0.4]),
                specular: .color([0.3, 0.3, 0.3]),
                shininess: 32
            )
        )
    ]

    var body: some View {
        RenderView { _, drawableSize in
            let aspect = drawableSize.height > 0 ? Float(drawableSize.width / drawableSize.height) : 1.0
            let projectionMatrix = float4x4.perspective(fovY: .pi / 4, aspect: aspect, near: 0.1, far: 1_000.0)
            let viewMatrix = cameraMatrix.inverse

            try RenderPass {
                if let skyboxTexture {
                    try SkyboxRenderPipeline(
                        projectionMatrix: projectionMatrix,
                        cameraMatrix: cameraMatrix,
                        rotation: simd_quatf(angle: .pi, axis: [0, 1, 0]),
                        texture: skyboxTexture
                    )
                }

                GridShader(
                    projectionMatrix: projectionMatrix,
                    cameraMatrix: cameraMatrix,
                    highlightedLines: [
                        .init(axis: .x, position: 0, width: 0.03, color: [1, 0.2, 0.2, 1]),
                        .init(axis: .y, position: 0, width: 0.03, color: [0.2, 0.4, 1, 1])
                    ]
                )

                if let lighting, let firstModel = models.first {
                    try BlinnPhongShader {
                        try ForEach(models) { model in
                            try Draw { encoder in
                                encoder.setVertexBuffers(of: model.mesh)
                                encoder.draw(model.mesh)
                            }
                            .blinnPhongMaterial(model.material)
                            .blinnPhongMatrices(
                                projectionMatrix: projectionMatrix,
                                viewMatrix: viewMatrix,
                                modelMatrix: model.modelMatrix,
                                cameraMatrix: cameraMatrix
                            )
                        }
                        .lighting(lighting)
                    }
                    .vertexDescriptor(firstModel.mesh.vertexDescriptor)
                    .depthCompare(function: .less, enabled: true)
                }

            }
        }
        .metalDepthStencilPixelFormat(.depth32Float)
        .interactiveCamera(rotation: $cameraRotation, distance: $cameraDistance, target: $cameraTarget)
        .frameTimingOverlay()
        .task {
            do {
                lighting = try Lighting(
                    ambientLightColor: [0.15, 0.15, 0.2],
                    lights: [
                        ([2, 5, 3], Light(type: .point, color: [1, 1, 1], intensity: 20))
                    ]
                )
                let device = _MTLCreateSystemDefaultDevice()
                let crossTexture = try device.makeTexture(name: "Skybox", bundle: .main)
                skyboxTexture = try device.makeTextureCubeFromCrossTexture(texture: crossTexture)
            } catch {
                fatalError("Failed to initialize BlinnPhong demo: \(error)")
            }
        }
    }
}

private struct Model: Identifiable {
    var id: String
    var mesh: MTKMesh
    var modelMatrix: float4x4
    var material: BlinnPhongMaterial
}

#Preview {
    BlinnPhongDemoView()
}
