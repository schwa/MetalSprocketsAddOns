import GeometryLite3D
import Interaction3D
import Metal
import MetalKit
import MetalSprockets
import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsUI
import MetalSupport
import simd
import SwiftUI

/// Hardware ray-traced shadows.
///
/// `AccelerationStructureManager` builds one primitive acceleration structure per mesh and
/// a single instance structure over them. `RayTracedShadowComputePass` then reconstructs
/// world position from the scene depth buffer and traces a shadow ray per pixel toward
/// each light, so shadows are decoupled from any shadow-map resolution.
struct RayTracedShadowsDemoView: View {
    @State private var camera = InteractionState(pitch: -.pi / 7, distance: 9, target: [0, 0.5, 0])
    @State private var scene: RayTracedShadowsDemoScene?
    @State private var shadowIntensity: Float = 0.85
    @State private var showShadows = true
    @State private var debugOverlay = false
    @State private var animate = true

    private var supportsRayTracing: Bool {
        _MTLCreateSystemDefaultDevice().supportsRaytracing
    }

    var body: some View {
        DemoLayoutView {
            if supportsRayTracing {
                TimelineView(.animation(paused: !animate)) { timeline in
                    Group {
                        if let scene {
                            RayTracedShadowsRenderView(
                                scene: scene,
                                camera: camera,
                                shadowIntensity: shadowIntensity,
                                showShadows: showShadows,
                                debugOverlay: debugOverlay
                            )
                        }
                    }
                    .onChange(of: timeline.date, initial: true) {
                        let position = RayTracedShadowsDemoScene.lightPosition(at: timeline.date.animationTime(wrappingEvery: .pi * 4))
                        scene?.lighting.setLightPosition(position, at: 0)
                    }
                }
                .demoCameraControls($camera)
            } else {
                ContentUnavailableView(
                    "Ray Tracing Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This GPU does not support Metal ray tracing.")
                )
            }
        } controls: {
            Toggle("Shadows", isOn: $showShadows)
            Toggle("Debug Overlay", isOn: $debugOverlay)
            Toggle("Animate Light", isOn: $animate)
            LabeledContent("Intensity") {
                Slider(value: $shadowIntensity, in: 0...1)
            }
        }
        .task {
            guard supportsRayTracing else {
                return
            }
            scene = try? RayTracedShadowsDemoScene()
        }
    }
}

private struct RayTracedShadowsRenderView: View {
    let scene: RayTracedShadowsDemoScene
    let camera: InteractionState
    let shadowIntensity: Float
    let showShadows: Bool
    let debugOverlay: Bool

    var body: some View {
        RenderView { _, drawableSize in
            let projection = camera.projectionMatrix(drawableSize: drawableSize)
            RayTracedShadowsElement(
                scene: scene,
                viewProjection: projection * camera.viewMatrix,
                shadowIntensity: shadowIntensity,
                showShadows: showShadows,
                debug: debugOverlay
            )
        }
        // `.id` forces a fresh element tree when `debug` flips: the debug flag is a
        // function constant baked into the compute kernel at construction time.
        .id(debugOverlay)
        .metalDepthStencilPixelFormat(.depth32Float)
        .metalDepthStencilAttachmentTextureUsage([.renderTarget, .shaderRead])
        .metalFramebufferOnly(false)
        .metalClearColor(RayTracedShadowsDemoScene.clearColor)
    }
}

/// Meshes, their acceleration structures and the lighting, built once.
///
/// `@unchecked Sendable` mirrors the rest of MetalSprockets: the element tree is walked on a
/// single thread, and this object is only ever touched from there.
final class RayTracedShadowsDemoScene: @unchecked Sendable {
    typealias Model = (mesh: MTKMesh, transform: simd_float4x4, color: SIMD3<Float>)

    static let clearColor = MTLClearColor(red: 0.05, green: 0.06, blue: 0.09, alpha: 1)

    /// The light orbits the scene; `time` is in seconds.
    static func lightPosition(at time: Float) -> SIMD3<Float> {
        let angle = time * 0.5
        return [cos(angle) * 5, 6, sin(angle) * 5]
    }

    let models: [Model]
    let accelerationStructureManager: AccelerationStructureManager
    let lighting: Lighting

    init() throws {
        models = [
            // Finely tessellated so the ray-traced self-shadow edge stays smooth (#58).
            (.sphere(radius: 0.6, segments: 192), .init(translation: [-1.4, 0.6, 0]), [0.85, 0.4, 0.3]),
            (.box(extent: [1, 2, 1]), .init(translation: [1.4, 1, 0]), [0.3, 0.5, 0.9]),
            // MTKMesh.plane is in the XY plane; lay it flat on y = 0.
            (.plane(width: 12, height: 12), .init(simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])), [0.8, 0.8, 0.82])
        ]
        var manager = try AccelerationStructureManager()
        try manager.build(
            meshes: models.map(\.mesh),
            instances: models.enumerated().map { index, model in
                AccelerationStructureManager.Instance(meshIndex: index, transform: model.transform)
            }
        )
        accelerationStructureManager = manager
        lighting = try Lighting(
            ambientLightColor: [0.15, 0.15, 0.2],
            lights: [([4, 6, 3], Light(type: .point, color: [1, 1, 1], intensity: 30))]
        )
    }
}

struct RayTracedShadowsElement: Element {
    var scene: RayTracedShadowsDemoScene
    var viewProjection: simd_float4x4
    var shadowIntensity: Float
    var showShadows: Bool
    var debug: Bool

    @MSEnvironment(\.renderPassDescriptor)
    private var renderPassDescriptor

    var body: some Element {
        get throws {
            try RenderPass(label: "Scene") {
                ForEach(Array(scene.models.enumerated()), id: \.offset) { _, model in
                    try FlatShader(
                        modelViewProjection: viewProjection * model.transform,
                        textureSpecifier: ColorSource.color(model.color)
                    ) {
                        Draw(mesh: model.mesh)
                        .vertexBuffers(of: model.mesh)
                    }
                    .vertexDescriptor(MTLVertexDescriptor(model.mesh.vertexDescriptor))
                    .depthCompare(function: .less, enabled: true)
                }
            }
            .renderPassDescriptorModifier { descriptor in
                descriptor.depthAttachment.storeAction = .store
            }

            if showShadows,
               let depthTexture = renderPassDescriptor?.depthAttachment.texture,
               let colorTexture = renderPassDescriptor?.colorAttachments[0].texture {
                try RayTracedShadowComputePass(
                    sceneDepthTexture: depthTexture,
                    outputTexture: colorTexture,
                    accelerationStructureManager: scene.accelerationStructureManager,
                    lighting: scene.lighting,
                    inverseViewProjection: viewProjection.inverse,
                    shadowIntensity: shadowIntensity,
                    debug: debug
                )
            }
        }
    }
}

#Preview {
    RayTracedShadowsDemoView()
}
