import CoreText
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsUI
import MetalSupport
import simd
import SwiftUI

/// Slug-style glyph rendering: outlines stay in curve/band textures and are resolved in the
/// fragment shader, so text is resolution-independent and stays sharp at any camera distance.
///
/// The expensive half is `SlugTextMeshBuilder`, which lays out CoreText runs, builds a font
/// atlas per font, and packs every mesh into shared vertex/index buffers. That happens once;
/// each frame only updates the per-mesh model matrices in the scene's shared buffer.
struct SlugTextDemoView: View {
    @State private var camera = OrbitCamera(pitch: -.pi / 12, distance: 900, target: [0, 0, 0])
    @State private var scene: SlugScene?
    @State private var text = "Metal\nSprockets"
    @State private var fontSize: CGFloat = 144
    @State private var wireframe = false
    @State private var spin = true
    @State private var angle: Float = 0

    var body: some View {
        DemoLayout {
            TimelineView(.animation(paused: !spin)) { timeline in
                renderView
                    .onChange(of: timeline.date, initial: true) {
                        // The spin uses angle * 0.4, so 5π is one full turn.
                        angle = timeline.date.animationTime(wrappingEvery: .pi * 5)
                        if let scene {
                            SlugTextDemoScene.setSpin(angle, in: scene)
                        }
                    }
            }
            .orbitCamera($camera)
        } controls: {
            TextField("Text", text: $text, axis: .vertical)
                .lineLimit(1...4)
            LabeledContent("Font Size") {
                Slider(value: $fontSize, in: 24...400)
            }
            Toggle("Spin", isOn: $spin)
            Toggle("Wireframe", isOn: $wireframe)
        }
        .task(id: TextKey(text: text, fontSize: fontSize)) {
            scene = try? SlugTextDemoScene.makeScene(text: text, fontSize: fontSize)
        }
    }

    @ViewBuilder
    private var renderView: some View {
        if let scene, let mesh = scene.meshes.first {
            RenderView { _, drawableSize in
                try SlugTextDemoScene.element(scene: scene, camera: camera, drawableSize: drawableSize, wireframe: wireframe)
            }
            .id(ObjectIdentifier(scene))
            .metalClearColor(SlugTextDemoScene.clearColor)
            .onAppear {
                camera = SlugTextDemoScene.framingCamera(for: mesh, pitch: camera.pitch)
            }
        }
    }
}

/// The demo's text scene, separate from the view so tests can render it offscreen.
enum SlugTextDemoScene {
    static let clearColor = MTLClearColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1)

    static func makeScene(text: String, fontSize: CGFloat) throws -> SlugScene {
        let device = _MTLCreateSystemDefaultDevice()
        let builder = SlugTextMeshBuilder(device: device)
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: CGColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)
            ]
        )
        builder.buildMesh(attributedString: attributed)
        return try builder.finalize()
    }

    /// Frames the text: the mesh is laid out in CoreText points with an arbitrary origin.
    static func framingCamera(for mesh: SlugTextMesh, pitch: Float) -> OrbitCamera {
        OrbitCamera(
            pitch: pitch,
            distance: Float(max(mesh.bounds.width, mesh.bounds.height)) * 2,
            target: [Float(mesh.bounds.midX), Float(mesh.bounds.midY), 0]
        )
    }

    static func element(scene: SlugScene, camera: OrbitCamera, drawableSize: CGSize, wireframe: Bool) throws -> some Element {
        // Text is laid out in points, so the camera sits hundreds of units away.
        let projection = camera.projectionMatrix(drawableSize: drawableSize, zClip: 1...(camera.distance * 4))
        let constants = SlugFrameConstants(
            viewProjectionMatrix: projection * camera.viewMatrix,
            viewportSize: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))
        )
        return try RenderPass {
            try SlugTextRenderPipeline(scene: scene, frameConstants: constants, wireframe: wireframe)
        }
    }

    /// Spins the first mesh about its own vertical axis. The rotation is `angle * 0.4`.
    static func setSpin(_ angle: Float, in scene: SlugScene) {
        guard let mesh = scene.meshes.first else {
            return
        }
        // Spin around the text's own centre rather than the layout origin.
        let centre = SIMD3<Float>(Float(mesh.bounds.midX), Float(mesh.bounds.midY), 0)
        let transform = simd_float4x4(translation: centre)
            * simd_float4x4(simd_quatf(angle: angle * 0.4, axis: [0, 1, 0]))
            * simd_float4x4(translation: -centre)
        scene.withModelMatrices { matrices in
            matrices[0] = transform
        }
    }
}

/// Rebuilding the scene is expensive, so it is keyed on exactly the inputs that change it.
private struct TextKey: Equatable {
    var text: String
    var fontSize: CGFloat
}

#Preview {
    SlugTextDemoView()
}
