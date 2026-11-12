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
        case .graphicsContext3D, .jumpFloodOutline: true
        default: false
        }
    }
}

/// The selected demo's immersive version, in front of the viewer. Demos without one draw nothing.
struct ImmersiveDemoScene: Element {
    let context: ImmersiveContext

    // Read-only after creation; built once rather than every frame.
    nonisolated(unsafe) private static let sphere = MetalMesh(mtkMesh: MTKMesh.sphere(extent: [0.8, 0.8, 0.8]))

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
