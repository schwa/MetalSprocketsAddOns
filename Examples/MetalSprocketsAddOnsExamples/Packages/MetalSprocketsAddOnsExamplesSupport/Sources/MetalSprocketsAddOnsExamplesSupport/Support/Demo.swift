import SwiftUI

/// One entry in the examples app's sidebar.
public struct Demo: Identifiable, Sendable {
    public var id: String { name }
    public var name: String
    public var systemImage: String
    public var summary: String
    public var content: @MainActor @Sendable () -> AnyView

    init(name: String, systemImage: String, summary: String, content: @escaping @MainActor @Sendable () -> some View) {
        self.name = name
        self.systemImage = systemImage
        self.summary = summary
        self.content = { AnyView(content()) }
    }
}

public extension Demo {
    /// Every demo shipped by the examples app, in presentation order.
    static let all: [Demo] = [
        Demo(
            name: "Blinn-Phong",
            systemImage: "light.max",
            summary: "Argument-buffer lighting and materials with two orbiting point lights."
        ) {
            BlinnPhongDemoView()
        },
        Demo(
            name: "Shadow Map",
            systemImage: "cube.transparent",
            summary: "Depth pass from the light's point of view, then a compute shadow-mask pass."
        ) {
            ShadowMapDemoView()
        },
        Demo(
            name: "Ray-Traced Shadows",
            systemImage: "sparkles",
            summary: "Acceleration structures plus a compute pass that traces shadow rays."
        ) {
            RayTracedShadowsDemoView()
        },
        Demo(
            name: "GraphicsContext3D",
            systemImage: "scribble.variable",
            summary: "Canvas-style stroking and filling of 3D paths at pixel-exact line widths."
        ) {
            GraphicsContext3DDemoView()
        },
        Demo(
            name: "Slug Text",
            systemImage: "textformat",
            summary: "Resolution-independent glyph rendering from a CoreText attributed string."
        ) {
            SlugTextDemoView()
        },
        Demo(
            name: "Debug Shading",
            systemImage: "square.3.layers.3d",
            summary: "Per-attribute debug visualisations for diagnosing vertex-layout problems."
        ) {
            DebugShadingDemoView()
        }
    ]
}
