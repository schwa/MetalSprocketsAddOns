import GeometryLite3D
import Metal
import MetalKit
import MetalSprockets
import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsUI
import MetalSupport
import simd
import SwiftUI

/// Blinn-Phong shading driven by `Lighting` and `BlinnPhongMaterial`.
///
/// The interesting part is the argument-buffer plumbing: `Lighting` owns two `MTLBuffer`s
/// (lights and positions) that are packed into an argument buffer once per frame, and
/// `BlinnPhongMaterial` packs its `ColorSource`s the same way. Both are attached with a
/// single modifier each, and the lights are mutated in place between frames.
struct BlinnPhongDemoView: View {
    private struct Model: Identifiable {
        var id: String
        var mesh: MTKMesh
        var modelMatrix: simd_float4x4
        var material: BlinnPhongMaterial
    }

    @State private var camera = OrbitCamera(pitch: -.pi / 8, distance: 6, target: [0, 0.2, 0])
    @State private var lighting: Lighting?
    @State private var lightPositions: [SIMD3<Float>] = [[0, 2, 3], [0, 2, -3]]
    @State private var shininess: Float = 64
    @State private var animate = true
    @State private var showGrid = true

    private let models: [Model] = [
        Model(
            id: "sphere",
            mesh: .sphere(extent: [1.2, 1.2, 1.2]),
            modelMatrix: .init(translation: [-1, 0, 0]),
            material: BlinnPhongMaterial(
                ambient: .color([0.08, 0.03, 0.03]),
                diffuse: .color([0.75, 0.25, 0.2]),
                specular: .color([1, 1, 1]),
                shininess: 64
            )
        ),
        Model(
            id: "box",
            mesh: .box(extent: [1, 1, 1]),
            modelMatrix: .init(translation: [1.2, 0, 0]),
            material: BlinnPhongMaterial(
                ambient: .color([0.03, 0.03, 0.08]),
                diffuse: .color([0.2, 0.35, 0.8]),
                specular: .color([1, 1, 1]),
                shininess: 64
            )
        )
    ]

    var body: some View {
        DemoLayout {
            TimelineView(.animation(paused: !animate)) { timeline in
                renderView
                    .onChange(of: timeline.date, initial: true) {
                        updateLights(at: timeline.date)
                    }
            }
            .orbitCamera($camera)
        } controls: {
            Toggle("Animate Lights", isOn: $animate)
            Toggle("Grid", isOn: $showGrid)
            LabeledContent("Shininess") {
                Slider(value: $shininess, in: 1...256)
            }
        }
        .task {
            lighting = try? Lighting(
                ambientLightColor: [0.12, 0.12, 0.16],
                lights: [
                    (lightPositions[0], Light(type: .point, color: [1, 0.95, 0.85], intensity: 20)),
                    (lightPositions[1], Light(type: .point, color: [0.4, 0.7, 1], intensity: 20))
                ]
            )
        }
    }

    @ViewBuilder
    private var renderView: some View {
        if let lighting {
            RenderView { _, drawableSize in
                let projection = camera.projectionMatrix(drawableSize: drawableSize)
                try RenderPass {
                    if showGrid {
                        GridShader(projectionMatrix: projection, cameraMatrix: camera.cameraMatrix)
                    }
                    if let first = models.first {
                        try BlinnPhongShader {
                            try ForEach(models) { model in
                                try Draw { encoder in
                                    encoder.setVertexBuffers(of: model.mesh)
                                    encoder.draw(model.mesh)
                                }
                                .blinnPhongMaterial(model.material.withShininess(shininess))
                                .blinnPhongMatrices(
                                    projectionMatrix: projection,
                                    viewMatrix: camera.viewMatrix,
                                    modelMatrix: model.modelMatrix,
                                    cameraMatrix: camera.cameraMatrix
                                )
                            }
                            .lighting(lighting)
                        }
                        .vertexDescriptor(first.mesh.vertexDescriptor)
                        .depthCompare(function: .less, enabled: true)
                    }
                }
            }
            .metalDepthStencilPixelFormat(.depth32Float)
            .metalClearColor(MTLClearColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1))
        }
    }

    private func updateLights(at date: Date) {
        let t = Float(date.timeIntervalSinceReferenceDate)
        lightPositions[0] = [cos(t) * 3, 2, sin(t) * 3]
        lightPositions[1] = [cos(-t * 0.6) * 3, 1.5, sin(-t * 0.6) * 3]
        for (index, position) in lightPositions.enumerated() {
            lighting?.setLightPosition(position, at: index)
        }
    }
}

private extension BlinnPhongMaterial {
    func withShininess(_ value: Float) -> Self {
        var copy = self
        copy.shininess = value
        return copy
    }
}

#Preview {
    BlinnPhongDemoView()
}
