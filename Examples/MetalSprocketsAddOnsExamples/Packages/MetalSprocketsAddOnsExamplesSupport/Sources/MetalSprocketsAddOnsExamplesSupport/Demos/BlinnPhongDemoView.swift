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
/// single modifier each, and the lights are updated between frames (copy-on-write, so frames
/// still on the GPU keep their own light data).
struct BlinnPhongDemoView: View {
    @State private var camera = OrbitCamera(pitch: -.pi / 8, distance: 6, target: [0, 0.2, 0])
    @State private var lighting: Lighting?
    @State private var shininess: Float = 64
    @State private var animate = true
    @State private var showGrid = true

    private let scene = BlinnPhongDemoScene()

    var body: some View {
        DemoLayoutView {
            TimelineView(.animation(paused: !animate)) { timeline in
                Group {
                    if let lighting {
                        BlinnPhongRenderView(scene: scene, lighting: lighting, camera: camera, shininess: shininess, showGrid: showGrid)
                    }
                }
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
            lighting = try? BlinnPhongDemoScene.makeLighting()
        }
    }

    private func updateLights(at date: Date) {
        // 10π is a whole number of turns at both rates (1 and 0.6).
        let positions = BlinnPhongDemoScene.lightPositions(at: date.animationTime(wrappingEvery: .pi * 10))
        for (index, position) in positions.enumerated() {
            lighting?.setLightPosition(position, at: index)
        }
    }
}

private struct BlinnPhongRenderView: View {
    let scene: BlinnPhongDemoScene
    let lighting: Lighting
    let camera: OrbitCamera
    let shininess: Float
    let showGrid: Bool

    var body: some View {
        RenderView { _, drawableSize in
            try scene.element(
                lighting: lighting,
                camera: camera,
                projection: camera.projectionMatrix(drawableSize: drawableSize),
                shininess: shininess,
                showGrid: showGrid
            )
        }
        .metalDepthStencilPixelFormat(.depth32Float)
        .metalClearColor(BlinnPhongDemoScene.clearColor)
    }
}

/// The demo's models and per-frame scene, separate from the view so tests can render it offscreen.
struct BlinnPhongDemoScene {
    struct Model: Identifiable {
        var id: String
        var mesh: MTKMesh
        var modelMatrix: simd_float4x4
        var material: BlinnPhongMaterial
    }

    static let clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)

    let models: [Model] = [
        Model(
            id: "sphere",
            // MDLMesh sphere extents are radii; rest the sphere on the grid.
            mesh: .sphere(extent: [0.6, 0.6, 0.6]),
            modelMatrix: .init(translation: [-1, 0.6, 0]),
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
            modelMatrix: .init(translation: [1.2, 0.5, 0]),
            material: BlinnPhongMaterial(
                ambient: .color([0.03, 0.03, 0.08]),
                diffuse: .color([0.2, 0.35, 0.8]),
                specular: .color([1, 1, 1]),
                shininess: 64
            )
        )
    ]

    static func makeLighting() throws -> Lighting {
        let positions = lightPositions(at: 0)
        return try Lighting(
            ambientLightColor: [0.12, 0.12, 0.16],
            lights: [
                (positions[0], Light(type: .point, color: [1, 0.95, 0.85], intensity: 20)),
                (positions[1], Light(type: .point, color: [0.4, 0.7, 1], intensity: 20))
            ]
        )
    }

    /// Two lights orbiting in opposite directions; `time` is in seconds.
    static func lightPositions(at time: Float) -> [SIMD3<Float>] {
        [
            [cos(time) * 3, 2, sin(time) * 3],
            [cos(-time * 0.6) * 3, 1.5, sin(-time * 0.6) * 3]
        ]
    }

    func element(
        lighting: Lighting,
        camera: OrbitCamera,
        projection: simd_float4x4,
        shininess: Float,
        showGrid: Bool
    ) throws -> some Element {
        try RenderPass {
            if showGrid {
                GridShader(projectionMatrix: projection, cameraMatrix: camera.cameraMatrix)
            }
            if let first = models.first {
                try BlinnPhongShader {
                    try ForEach(models) { model in
                        try Draw(mesh: model.mesh)
                        .vertexBuffers(of: model.mesh)
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
