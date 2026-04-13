import SwiftUI

struct ContentView: View {
    var body: some View {
        #if os(visionOS)
        TabView {
            Tab("Cube", systemImage: "cube") {
                VisionOSDemoView()
            }
            Tab("Matrix Rain", systemImage: "chevron.left.forwardslash.chevron.right") {
                ImmersiveMatrixRainView()
            }
        }
        #elseif os(iOS)
        MobileDemoView()
        #else
        RenderDemoView()
        #endif
    }
}

#Preview {
    ContentView()
}