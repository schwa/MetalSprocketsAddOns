import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsAddOns
import MetalSprocketsUI
import simd
import SwiftUI

/// `GraphicsContext3D` is a `SwiftUI.Canvas`-shaped API for 3D line art.
///
/// Strokes are expanded to geometry in *screen* space by an object/mesh shader pipeline, so
/// line width is in pixels and stays constant regardless of depth, while joins and caps are
/// generated per segment. Fills are triangulated on the path's dominant plane.
struct GraphicsContext3DDemoView: View {
    @State private var camera = OrbitCamera(pitch: -.pi / 6, distance: 5)
    @State private var lineWidth: Float = 6
    @State private var lineCap: CGLineCap = .round
    @State private var lineJoin: CGLineJoin = .round
    @State private var showFill = true
    @State private var debugWireframe = false

    var body: some View {
        DemoLayoutView {
            RenderView { _, drawableSize in
                let projection = camera.projectionMatrix(drawableSize: drawableSize)
                let viewport = SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))
                try RenderPass {
                    GraphicsContext3DRenderPipeline(
                        context: context,
                        viewProjection: projection * camera.viewMatrix,
                        viewport: viewport,
                        debugWireframe: debugWireframe
                    )
                }
            }
            .metalDepthStencilPixelFormat(.depth32Float)
            .metalClearColor(GraphicsContext3DDemoScene.clearColor)
            .orbitCamera($camera)
        } controls: {
            LabeledContent("Line Width") {
                Slider(value: $lineWidth, in: 1...30)
            }
            Picker("Cap", selection: $lineCap) {
                Text("Butt").tag(CGLineCap.butt)
                Text("Round").tag(CGLineCap.round)
                Text("Square").tag(CGLineCap.square)
            }
            Picker("Join", selection: $lineJoin) {
                Text("Miter").tag(CGLineJoin.miter)
                Text("Round").tag(CGLineJoin.round)
                Text("Bevel").tag(CGLineJoin.bevel)
            }
            Toggle("Filled Quad", isOn: $showFill)
            Toggle("Debug Wireframe", isOn: $debugWireframe)
        }
    }

    private var context: GraphicsContext3D {
        GraphicsContext3DDemoScene.context(lineWidth: lineWidth, lineCap: lineCap, lineJoin: lineJoin, showFill: showFill)
    }
}

/// The demo's drawing, separate from the view so tests can render it offscreen.
enum GraphicsContext3DDemoScene {
    static let clearColor = MTLClearColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1)

    static func context(lineWidth: Float, lineCap: CGLineCap, lineJoin: CGLineJoin, showFill: Bool) -> GraphicsContext3D {
        let style = StrokeStyle(lineWidth: CGFloat(lineWidth), lineCap: lineCap, lineJoin: lineJoin)
        return GraphicsContext3D { ctx in
            // Axis cross — the classic sanity check that world space maps where you expect.
            for (axis, color) in [(SIMD3<Float>(1, 0, 0), Color.red), ([0, 1, 0], .green), ([0, 0, 1], .blue)] {
                ctx.stroke(
                    Path3D { path in
                        path.move(to: -axis * 1.5)
                        path.addLine(to: axis * 1.5)
                    },
                    with: color,
                    lineWidth: 2
                )
            }

            // A closed polyline: exercises joins at every vertex and the closing segment.
            ctx.stroke(
                Path3D { path in
                    path.move(to: [-1, -0.8, 0.6])
                    path.addLine(to: [1, -0.8, 0.6])
                    path.addLine(to: [0, 1.1, 0.6])
                    path.closeSubpath()
                },
                with: .yellow,
                style: style
            )

            // A cubic curve: subdivided on the CPU, then stroked in screen space.
            ctx.stroke(
                Path3D { path in
                    path.move(to: [-1.4, 0.2, -0.8])
                    path.addCurve(to: [1.4, 0.2, -0.8], control1: [-0.5, 1.8, -0.8], control2: [0.5, -1.4, -0.8])
                },
                with: .cyan,
                style: style
            )

            if showFill {
                ctx.fill(
                    Path3D { path in
                        path.move(to: [-0.7, -1.3, -0.2])
                        path.addLine(to: [0.7, -1.3, -0.2])
                        path.addLine(to: [0.7, -0.1, -0.2])
                        path.addLine(to: [-0.7, -0.1, -0.2])
                        path.closeSubpath()
                    },
                    with: .orange.opacity(0.6)
                )
            }
        }
    }
}

#Preview {
    GraphicsContext3DDemoView()
}
