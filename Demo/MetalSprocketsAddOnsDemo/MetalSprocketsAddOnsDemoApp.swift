import DemoKit
import SwiftUI

#if os(visionOS)
import MetalSprockets
import MetalSprocketsUI
#endif

@main
struct MetalSprocketsAddOnsDemoApp: App {
    static let demos: [any DemoView.Type] = {
        var demos: [any DemoView.Type] = [
            RenderDemoView.self,
            GridDemoView.self,
            SkyboxDemoView.self,
            BlinnPhongDemoView.self,
            DebugShaderDemoView.self,
            TrivialMeshDemoView.self,
            GraphicsContext3DDemoView.self,
            SlugDebugDemoView.self,
            SlugTextPanelDemoView.self,
            SlugSpinningSphereDemoView.self,
            SlugMatrixRainDemoView.self,
        ]
        #if os(macOS)
        demos.append(SlugTerminalDemoView.self)
        #endif
        return demos
    }()

    var body: some Scene {
        #if os(visionOS)
        WindowGroup {
            ContentView()
        }
        #else
        DemoPickerScene(demos: Self.demos)
        #endif

        #if os(visionOS)
        // Immersive space for mixed reality rendering
        ImmersiveSpace(id: "ImmersiveCube") {
            ImmersiveRenderContent(progressive: false) { context in
                try ImmersiveRenderPass(context: context, label: "Cube") {
                    try ImmersiveCubeContent(context: context)
                }
            }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
        .upperLimbVisibility(.visible)

        ImmersiveSpace(id: "ImmersiveMatrixRain") {
            ImmersiveMatrixRainContent()
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
        #endif
    }
}