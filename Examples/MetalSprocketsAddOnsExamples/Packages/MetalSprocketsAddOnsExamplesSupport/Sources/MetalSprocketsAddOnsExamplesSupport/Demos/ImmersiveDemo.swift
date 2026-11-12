#if os(visionOS)
import Metal
import MetalKit
import MetalSprockets
import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
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
            // No foveation: the outline pass reads a full-resolution mask by pixel position, which a foveated
            // (rasterization-rate-mapped) pass would not match.
            ImmersiveRenderContent(foveation: false) { context in
                // Offscreen work goes outside the compositor's pass; ending it through the compositor's render
                // context would end the command buffer.
                ImmersiveDemoPrepass(context: context)
                    .immersiveRenderContext(nil)
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
        case .graphicsContext3D, .jumpFloodOutline, .slugText, .debugShading, .blinnPhong: true
        default: false
        }
    }
}

/// Per-frame values every immersive demo shares, and resources built once. The render loop is one actor, so the
/// shared state is only touched from it.
enum ImmersiveDemoShared {
    // Read-only after creation; built once rather than every frame.
    nonisolated(unsafe) static let debugShadingScene = DebugShadingDemoScene()
    nonisolated(unsafe) static let sphereMetalMesh = MetalMesh(mtkMesh: debugShadingScene.sphere)
    // Built once; each frame only updates its spin.
    nonisolated(unsafe) static let slugScene = try? SlugTextDemoScene.makeScene(text: "Metal\nSprockets", fontSize: 144)
    // One set, reused every frame. Frames in flight share it, which can show a stale outline for a frame.
    nonisolated(unsafe) static let outlineTextures = JumpFloodDemoTextures()
    static let outlineWidth: Float = 8
    nonisolated(unsafe) static let blinnPhongScene = BlinnPhongDemoScene()
    static let placementScale: Float = 0.2
    // The demo's lights, dimmed by the placement scale squared so falloff over the smaller distances looks the same.
    nonisolated(unsafe) static let blinnPhongLighting = try? Lighting(
        ambientLightColor: [0.12, 0.12, 0.16],
        lights: [
            ([0, 0, 0], Light(type: .point, color: [1, 0.95, 0.85], intensity: 20 * placementScale * placementScale)),
            ([0, 0, 0], Light(type: .point, color: [0.4, 0.7, 1], intensity: 20 * placementScale * placementScale))
        ]
    )

    static func views(_ context: ImmersiveContext) -> StereoViews {
        let viewProjections = (0 ..< context.viewCount).map { context.projectionMatrix(eye: $0) * context.viewMatrix(eye: $0) }
        return StereoViews(viewProjections: viewProjections, viewports: context.viewports)
    }

    /// About 1.2 m in front at eye height, scaled from the demos' ±1.5 units to about ±0.3 m, spinning.
    static func world(_ context: ImmersiveContext) -> float4x4 {
        let placement = float4x4(translation: [0, 1.3, -1.2]) * float4x4(scale: [placementScale, placementScale, placementScale])
        return placement * float4x4(simd_quatf(angle: Float(context.time) * 0.5, axis: [0, 1, 0]))
    }

    /// The Debug Shading sphere's model matrix, about 0.4 m across.
    static func sphereModelMatrix(_ context: ImmersiveContext) -> float4x4 {
        world(context) * float4x4(scale: [2, 2, 2])
    }

    /// The outline's mask and seeds: one slice per eye, sized to an eye's view.
    static func outlineMaskAndSeeds(_ context: ImmersiveContext) throws -> (mask: MTLTexture, seeds: MTLTexture) {
        let viewport = context.viewports[0]
        return try outlineTextures.textures(width: Int(viewport.width), height: Int(viewport.height), arrayLength: context.viewCount)
    }
}

/// Offscreen work before the compositor's pass: the Jump Flood Outlines demo's mask and flood.
struct ImmersiveDemoPrepass: Element {
    let context: ImmersiveContext

    var body: some Element {
        get throws {
            try Group {
                if ImmersiveDemoSelection.current == .jumpFloodOutline {
                    let (mask, seeds) = try ImmersiveDemoShared.outlineMaskAndSeeds(context)
                    let instance = SilhouetteMaskRenderPipeline.Instance(mesh: ImmersiveDemoShared.sphereMetalMesh, transform: ImmersiveDemoShared.sphereModelMatrix(context))
                    try RenderPass(label: "Immersive Silhouette Mask") {
                        SilhouetteMaskRenderPipeline(instances: [instance], views: ImmersiveDemoShared.views(context))
                    }
                    .renderPassDescriptorModifier { descriptor in
                        descriptor.colorAttachments[0].texture = mask
                        descriptor.colorAttachments[0].loadAction = .clear
                        descriptor.colorAttachments[0].storeAction = .store
                        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
                        descriptor.depthAttachment.texture = nil
                        descriptor.stencilAttachment.texture = nil
                        descriptor.renderTargetArrayLength = mask.arrayLength
                        descriptor.rasterizationRateMap = nil
                    }
                    JumpFloodPipeline(mask: mask, seeds: seeds, maximumDistance: ImmersiveDemoShared.outlineWidth)
                }
            }
        }
    }
}

/// The selected demo's immersive version, in front of the viewer. Demos without one draw nothing.
struct ImmersiveDemoScene: Element {
    let context: ImmersiveContext

    /// The Debug Shading demo's sphere with normals shown as colors, spinning.
    private func debugShading() throws -> some Element {
        let mesh = ImmersiveDemoShared.debugShadingScene.sphere
        let views = ImmersiveDemoShared.views(context)
        let modelMatrix = ImmersiveDemoShared.sphereModelMatrix(context)
        let normalMatrix = float3x3(modelMatrix.columns.0.xyz, modelMatrix.columns.1.xyz, modelMatrix.columns.2.xyz)
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
    /// The Debug Shading sphere with an outline from the prepass's mask and flood, drawn over everything.
    private func outlinedSphere() throws -> some Element {
        let (mask, seeds) = try ImmersiveDemoShared.outlineMaskAndSeeds(context)
        return try Group {
            try debugShading()
            JumpFloodOutlineRenderPipeline(mask: mask, seeds: seeds, color: [1, 0.8, 0.2, 1], width: ImmersiveDemoShared.outlineWidth, writesDepth: true, views: ImmersiveDemoShared.views(context))
        }
    }

    /// The Blinn-Phong demo's sphere and box with its two orbiting lights, placed and spun like the other demos.
    private func blinnPhong() throws -> some Element {
        let world = ImmersiveDemoShared.world(context)
        let views = ImmersiveDemoShared.views(context)
        let scene = ImmersiveDemoShared.blinnPhongScene
        let lighting = ImmersiveDemoShared.blinnPhongLighting
        for (index, position) in BlinnPhongDemoScene.lightPositions(at: Float(context.time)).enumerated() {
            let worldPosition = world * SIMD4<Float>(position, 1)
            lighting?.setLightPosition(SIMD3<Float>(worldPosition.x, worldPosition.y, worldPosition.z), at: index)
        }
        let cameraMatrix = context.viewMatrix(eye: 0).inverse
        return try Group {
            if let lighting, let first = scene.models.first {
                try BlinnPhongShader(viewCount: views.count) {
                    try ForEach(scene.models) { model in
                        try Draw { encoder in
                            views.configure(encoder)
                            encoder.draw(model.mesh)
                        }
                        .vertexBuffers(of: model.mesh)
                        .useResources(model.mesh.submeshes.map(\.indexBuffer.buffer), usage: .read, stages: .vertex)
                        .blinnPhongMaterial(model.material)
                        .blinnPhongMatrices(modelMatrix: world * model.modelMatrix, cameraMatrix: cameraMatrix, views: views)
                    }
                    .lighting(lighting)
                }
                .vertexDescriptor(first.mesh.vertexDescriptor)
                .depthCompare(function: .greater, writes: true)
            }
        }
    }

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
            let viewProjections = ImmersiveDemoShared.views(context).viewProjections
            let viewports = context.viewports
            let viewportSize = SIMD2<Float>(Float(viewports[0].width), Float(viewports[0].height))
            let world = ImmersiveDemoShared.world(context)
            let contextViews = StereoViews(viewProjections: viewProjections.map { $0 * world }, viewports: viewports)

            let drawing = GraphicsContext3DDemoScene.context(lineWidth: 6, lineCap: .round, lineJoin: .round, showFill: true)
            // The compositor uses reverse Z. visionOS shows color only where depth is written.
            return try Group {
                switch demo {
                case .graphicsContext3D:
                    GraphicsContext3DRenderPipeline(context: drawing, views: contextViews, viewport: viewportSize, depthCompareFunction: .greater, writesDepth: true)
                case .slugText:
                    if let scene = ImmersiveDemoShared.slugScene, let mesh = scene.meshes.first {
                        try slugText(scene: scene, mesh: mesh, viewProjections: viewProjections, viewports: viewports, viewportSize: viewportSize)
                    }
                case .debugShading:
                    try debugShading()
                case .blinnPhong:
                    try blinnPhong()
                case .jumpFloodOutline:
                    try outlinedSphere()
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
