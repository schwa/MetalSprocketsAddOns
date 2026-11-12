#if os(visionOS)
import Metal
import MetalKit
import MetalSprockets
import MetalSprocketsAddOns
import MetalSprocketsUI
import os
import simd
import SwiftMesh
import SwiftUI
import Synchronization

/// The immersive space's ID, opened by ``ImmersiveDemoToggle``.
public let immersiveDemoSpaceID = "AddOnsImmersive"

/// Draws the stereo-capable pipelines in a visionOS immersive space, both eyes at once.
public struct ImmersiveDemoSpace: Scene {
    public init() {
        // Nothing to configure.
    }

    public var body: some Scene {
        ImmersiveSpace(id: immersiveDemoSpaceID) {
            ImmersiveRenderContent { context in
                ImmersiveRenderPass(context: context, label: "AddOns Immersive") {
                    ImmersiveDemoScene(context: context)
                }
            }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}

/// The demo the immersive space draws: the sidebar's selection. The render loop runs off the main actor, so it reads
/// this rather than SwiftUI state.
enum ImmersiveDemoSelection {
    private static let selected = Mutex<Demo?>(nil)

    static var current: Demo? {
        get { selected.withLock { $0 } }
        set { selected.withLock { $0 = newValue } }
    }
}

extension Demo {
    /// Whether the demo has an immersive version. Others need stereo support first (#119-#125).
    var hasImmersiveVersion: Bool {
        switch self {
        case .graphicsContext3D, .jumpFloodOutline, .slugText, .debugShading: true
        default: false
        }
    }
}

/// The selected demo's immersive version, in front of the viewer. Demos without one draw nothing.
struct ImmersiveDemoScene: Element {
    let context: ImmersiveContext

    // Read-only after creation; built once rather than every frame.
    nonisolated(unsafe) private static let sphere = MetalMesh(mtkMesh: MTKMesh.sphere(extent: [0.8, 0.8, 0.8]))
    // Built once; each frame only updates its spin.
    nonisolated(unsafe) private static let slugScene = try? SlugTextDemoScene.makeScene(text: "Metal\nSprockets", fontSize: 144)

    nonisolated(unsafe) private static let debugShadingScene = DebugShadingDemoScene()

    /// The Debug Shading demo's sphere with normals shown as colors, spinning.
    private func debugShading(world: float4x4, viewProjections: [float4x4], viewports: [MTLViewport]) throws -> some Element {
        let mesh = Self.debugShadingScene.sphere
        let modelMatrix = world * float4x4(scale: [2, 2, 2])
        let normalMatrix = float3x3(modelMatrix.columns.0.xyz, modelMatrix.columns.1.xyz, modelMatrix.columns.2.xyz)
        let views = StereoViews(viewProjections: viewProjections, viewports: viewports)
        return try DebugRenderPipeline(
            modelMatrix: modelMatrix,
            normalMatrix: normalMatrix,
            debugMode: .normal,
            lightPosition: [0, 3, 0],
            cameraPosition: context.viewMatrix(eye: 0).inverse.columns.3.xyz,
            views: views
        ) {
            Draw { encoder in
                views.configure(encoder)
                encoder.draw(mesh)
            }
            .vertexBuffers(of: mesh)
            .useResources(mesh.submeshes.map(\.indexBuffer.buffer), usage: .read, stages: .vertex)
        }
        .vertexDescriptor(mesh.vertexDescriptor)
        .depthCompare(function: .greater, writes: true)
    }

    /// The Slug Text demo's text, about 0.6 m wide and 1.5 m in front at eye height, spinning.
    private func slugText(scene: SlugScene, mesh: SlugTextMesh, viewProjections: [float4x4], viewports: [MTLViewport], viewportSize: SIMD2<Float>) throws -> SlugTextRenderPipeline {
        SlugTextDemoScene.setSpin(Float(context.time), in: scene)
        // Text is laid out in points: centre it, then scale points to meters.
        let scale = 0.6 / Float(max(mesh.bounds.width, 1))
        let placement = float4x4(translation: [0, 1.3, -1.5])
            * float4x4(scale: [scale, scale, scale])
            * float4x4(translation: [-Float(mesh.bounds.midX), -Float(mesh.bounds.midY), 0])
        let constants = viewProjections.map { SlugFrameConstants(viewProjectionMatrix: $0 * placement, viewportSize: viewportSize) }
        return try SlugTextRenderPipeline(scene: scene, viewConstants: constants, viewports: viewports, reverseZ: true)
    }

    var body: some Element {
        get throws {
            let demo = ImmersiveDemoSelection.current
            let eyes = 0 ..< context.viewCount
            let viewProjections = eyes.map { context.projectionMatrix(eye: $0) * context.viewMatrix(eye: $0) }
            let viewports = context.viewports
            let viewportSize = SIMD2<Float>(Float(viewports[0].width), Float(viewports[0].height))

            // About 1.2 m in front at eye height, scaled from the demo's ±1.5 units to about ±0.3 m.
            let placement = float4x4(translation: [0, 1.3, -1.2]) * float4x4(scale: [0.2, 0.2, 0.2])
            let spin = float4x4(simd_quatf(angle: Float(context.time) * 0.5, axis: [0, 1, 0]))
            let world = placement * spin
            let contextViews = StereoViews(viewProjections: viewProjections.map { $0 * world }, viewports: viewports)
            let sphereViews = StereoViews(viewProjections: viewProjections, viewports: viewports)
            let sphereTransform = placement * float4x4(translation: [2.2, 0, 0]) * spin

            let drawing = GraphicsContext3DDemoScene.context(lineWidth: 6, lineCap: .round, lineJoin: .round, showFill: true)
            // The compositor uses reverse Z. visionOS shows color only where depth is written.
            return try Group {
                switch demo {
                case .graphicsContext3D:
                    GraphicsContext3DRenderPipeline(context: drawing, views: contextViews, viewport: viewportSize, depthCompareFunction: .greater, writesDepth: true)
                case .slugText:
                    if let scene = Self.slugScene, let mesh = scene.meshes.first {
                        try slugText(scene: scene, mesh: mesh, viewProjections: viewProjections, viewports: viewports, viewportSize: viewportSize)
                    }
                case .debugShading:
                    try debugShading(world: world, viewProjections: viewProjections, viewports: viewports)
                case .jumpFloodOutline:
                    // The silhouette mask only, for now; outlines are #125.
                    SilhouetteMaskRenderPipeline(instances: [.init(mesh: Self.sphere, transform: sphereTransform)], views: sphereViews, depthCompareFunction: .greater, writesDepth: true)
                default:
                    EmptyElement()
                }
            }
        }
    }
}

/// Opens or closes the immersive demo.
public struct ImmersiveDemoToggle: View {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var isOpen = false
    @State private var isTransitioning = false
    let demo: Demo?

    init(demo: Demo?) {
        self.demo = demo
    }

    public var body: some View {
        Button(isOpen ? "Exit Immersive" : "Immersive Demo", systemImage: "visionpro") {
            isTransitioning = true
            Task {
                if isOpen {
                    await dismissImmersiveSpace()
                    isOpen = false
                } else {
                    let result = await openImmersiveSpace(id: immersiveDemoSpaceID)
                    if case .opened = result {
                        isOpen = true
                    } else {
                        Logger(subsystem: "io.schwa.metal-sprockets-addons-examples", category: "immersive").error("openImmersiveSpace failed: \(String(describing: result), privacy: .public)")
                    }
                }
                isTransitioning = false
            }
        }
        // Leaving is always allowed; entering needs a demo with an immersive version.
        .disabled(isTransitioning || (!isOpen && demo?.hasImmersiveVersion != true))
        .onChange(of: demo, initial: true) {
            ImmersiveDemoSelection.current = demo
        }
    }
}
#endif
