import SwiftUI

/// One entry in the examples app's sidebar.
public enum Demo: String, CaseIterable, Identifiable, Sendable {
    case blinnPhong
    case shadowMap
    case rayTracedShadows
    case graphicsContext3D
    case slugText
    case debugShading

    public var id: Self { self }

    /// Every demo shipped by the examples app, in presentation order.
    static var all: [Self] { allCases }

    var name: String {
        switch self {
        case .blinnPhong: "Blinn-Phong"
        case .shadowMap: "Shadow Map"
        case .rayTracedShadows: "Ray-Traced Shadows"
        case .graphicsContext3D: "GraphicsContext3D"
        case .slugText: "Slug Text"
        case .debugShading: "Debug Shading"
        }
    }

    var systemImage: String {
        switch self {
        case .blinnPhong: "light.max"
        case .shadowMap: "cube.transparent"
        case .rayTracedShadows: "sparkles"
        case .graphicsContext3D: "scribble.variable"
        case .slugText: "textformat"
        case .debugShading: "square.3.layers.3d"
        }
    }

    var summary: String {
        switch self {
        case .blinnPhong: "Argument-buffer lighting and materials with two orbiting point lights."
        case .shadowMap: "Depth pass from the light's point of view, then a compute shadow-mask pass."
        case .rayTracedShadows: "Acceleration structures plus a compute pass that traces shadow rays."
        case .graphicsContext3D: "Canvas-style stroking and filling of 3D paths at pixel-exact line widths."
        case .slugText: "Resolution-independent glyph rendering from a CoreText attributed string."
        case .debugShading: "Per-attribute debug visualisations for diagnosing vertex-layout problems."
        }
    }
}

/// The selected demo's view.
struct DemoView: View {
    let demo: Demo

    var body: some View {
        switch demo {
        case .blinnPhong: BlinnPhongDemoView()
        case .shadowMap: ShadowMapDemoView()
        case .rayTracedShadows: RayTracedShadowsDemoView()
        case .graphicsContext3D: GraphicsContext3DDemoView()
        case .slugText: SlugTextDemoView()
        case .debugShading: DebugShadingDemoView()
        }
    }
}
