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

/// Shadow mapping as three passes in one frame.
///
/// 1. `ShadowMapDepthPass` renders every caster from the light's point of view into a
///    depth texture array — one array slice per light, each with its own render pass.
/// 2. The scene is drawn normally, storing depth.
/// 3. `ShadowMaskPass` is a compute pass that reads scene depth, reprojects each pixel
///    into light space, and darkens the drawable in place.
///
/// Step 3 is why the view asks for a readable depth attachment and a non-framebuffer-only
/// drawable: the compute kernel needs to sample one and write the other.
struct ShadowMapDemoView: View {
    @State private var camera = OrbitCamera(pitch: -.pi / 7, distance: 9, target: [0, 0.5, 0])
    @State private var shadowMap: ShadowMap?
    @State private var lightPosition: SIMD3<Float> = [4, 6, 3]
    @State private var shadowIntensity: Float = 0.8
    @State private var depthBias: Float = 2
    @State private var slopeScale: Float = 4
    @State private var resolution = 1_024
    @State private var showShadows = true
    @State private var animate = true

    private let scene = ShadowMapDemoScene()

    var body: some View {
        DemoLayoutView {
            TimelineView(.animation(paused: !animate)) { timeline in
                Group {
                    if let shadowMap {
                        ShadowMapRenderView(
                            scene: scene,
                            shadowMap: shadowMap,
                            camera: camera,
                            lightPosition: lightPosition,
                            shadowIntensity: shadowIntensity,
                            depthBias: depthBias,
                            slopeScale: slopeScale,
                            showShadows: showShadows
                        )
                    }
                }
                .onChange(of: timeline.date, initial: true) {
                    lightPosition = ShadowMapDemoScene.lightPosition(at: timeline.date.animationTime(wrappingEvery: .pi * 4))
                }
            }
            .orbitCamera($camera)
        } controls: {
            Toggle("Shadows", isOn: $showShadows)
            Toggle("Animate Light", isOn: $animate)
            LabeledContent("Intensity") {
                Slider(value: $shadowIntensity, in: 0...1)
            }
            LabeledContent("Depth Bias") {
                Slider(value: $depthBias, in: 0...10)
            }
            LabeledContent("Slope Scale") {
                Slider(value: $slopeScale, in: 0...10)
            }
            Picker("Resolution", selection: $resolution) {
                ForEach([256, 512, 1_024, 2_048], id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
        }
        .task(id: resolution) {
            shadowMap = try? ShadowMap(resolution: resolution, lightCount: 1)
        }
    }
}

private struct ShadowMapRenderView: View {
    let scene: ShadowMapDemoScene
    let shadowMap: ShadowMap
    let camera: OrbitCamera
    let lightPosition: SIMD3<Float>
    let shadowIntensity: Float
    let depthBias: Float
    let slopeScale: Float
    let showShadows: Bool

    var body: some View {
        RenderView { _, drawableSize in
            let projection = camera.projectionMatrix(drawableSize: drawableSize)
            scene.element(
                shadowMap: shadowMap,
                lightPosition: lightPosition,
                viewProjection: projection * camera.viewMatrix,
                shadowIntensity: shadowIntensity,
                depthBias: depthBias,
                slopeScale: slopeScale,
                showShadows: showShadows
            )
        }
        .metalDepthStencilPixelFormat(.depth32Float)
        .metalDepthStencilAttachmentTextureUsage([.renderTarget, .shaderRead])
        .metalFramebufferOnly(false)
        .metalClearColor(ShadowMapDemoScene.clearColor)
    }
}

/// The demo's models and per-frame scene, separate from the view so tests can render it offscreen.
struct ShadowMapDemoScene {
    // MDLMesh sphere extents are radii.
    let sphere = MTKMesh.sphere(extent: [0.6, 0.6, 0.6])
    let box = MTKMesh.box(extent: [1, 2, 1])
    let ground = MTKMesh.plane(width: 12, height: 12)

    let sphereTransform = simd_float4x4(translation: [-1.4, 0.6, 0])
    let boxTransform = simd_float4x4(translation: [1.4, 1, 0])
    // MTKMesh.plane is in the XY plane; lay it flat on y = 0.
    let groundTransform = simd_float4x4(simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]))

    static let clearColor = MTLClearColor(red: 0.05, green: 0.06, blue: 0.09, alpha: 1)

    /// The light orbits the scene; `time` is in seconds.
    static func lightPosition(at time: Float) -> SIMD3<Float> {
        let angle = time * 0.5
        return [cos(angle) * 5, 6, sin(angle) * 5]
    }

    func element(
        shadowMap: ShadowMap,
        lightPosition: SIMD3<Float>,
        viewProjection: simd_float4x4,
        shadowIntensity: Float,
        depthBias: Float,
        slopeScale: Float,
        showShadows: Bool
    ) -> some Element {
        var shadowMap = shadowMap
        shadowMap.depthBias = depthBias
        shadowMap.slopeScale = slopeScale
        shadowMap.updateDirectionalLight(at: 0, position: lightPosition, orthoSize: 8, near: 0.1, far: 30)
        return ShadowScene(
            shadowMap: shadowMap,
            viewProjection: viewProjection,
            shadowIntensity: shadowIntensity,
            showShadows: showShadows,
            casters: [
                (sphere, sphereTransform, [0.85, 0.4, 0.3]),
                (box, boxTransform, [0.3, 0.5, 0.9])
            ],
            ground: (ground, groundTransform, [0.8, 0.8, 0.82])
        )
    }
}

/// The three-pass shadow chain, split out so the sibling ordering is obvious:
/// `ShadowMapDepthPass` and `ShadowMaskPass` each open their own encoder and therefore
/// must be siblings of the scene pass, never nested inside it.
private struct ShadowScene: Element {
    typealias Model = (mesh: MTKMesh, transform: simd_float4x4, color: SIMD3<Float>)

    var shadowMap: ShadowMap
    var viewProjection: simd_float4x4
    var shadowIntensity: Float
    var showShadows: Bool
    var casters: [Model]
    var ground: Model

    @MSEnvironment(\.renderPassDescriptor)
    private var renderPassDescriptor

    var body: some Element {
        get throws {
            let models = casters + [ground]

            if showShadows, let first = casters.first {
                try ShadowMapDepthPass(shadowMap: shadowMap, vertexDescriptor: first.mesh.vertexDescriptor) {
                    ForEach(Array(models.enumerated()), id: \.offset) { _, model in
                        Draw(mesh: model.mesh)
                        .vertexBuffers(of: model.mesh)
                        .parameter("modelMatrix", functionType: .vertex, value: model.transform)
                    }
                }
            }

            try RenderPass(label: "Scene") {
                ForEach(Array(models.enumerated()), id: \.offset) { _, model in
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
                // The mask pass samples this depth buffer, so it has to survive the pass.
                descriptor.depthAttachment.storeAction = .store
            }

            if showShadows,
               let depthTexture = renderPassDescriptor?.depthAttachment.texture,
               let colorTexture = renderPassDescriptor?.colorAttachments[0].texture {
                try ShadowMaskPass(
                    sceneDepthTexture: depthTexture,
                    outputTexture: colorTexture,
                    shadowMap: shadowMap,
                    inverseViewProjection: viewProjection.inverse,
                    shadowIntensity: shadowIntensity
                )
            }
        }
    }
}

#Preview {
    ShadowMapDemoView()
}
