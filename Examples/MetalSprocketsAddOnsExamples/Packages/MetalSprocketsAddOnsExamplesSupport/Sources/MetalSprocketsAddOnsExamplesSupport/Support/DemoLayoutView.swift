import MetalSprocketsUI
import SwiftUI

/// Shared chrome for every demo: the render surface fills the window with a frame rate HUD, and
/// the demo's controls sit in an inspector so the demos themselves only describe their own knobs.
struct DemoLayoutView<Content: View, Controls: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var controls: Controls

    @State private var showsInspector = true

    var body: some View {
        content
            .ignoresSafeArea()
            // After ignoresSafeArea so the HUD stays clear of the toolbar.
            .modifier(FrameRateHUDModifier())
            #if os(visionOS)
            // visionOS has no inspector; show the controls in an ornament beside the window.
            .ornament(visibility: showsInspector ? .visible : .hidden, attachmentAnchor: .scene(.trailing), contentAlignment: .leading) {
                Form {
                    controls
                }
                .formStyle(.grouped)
                .frame(width: 300, height: 480)
                .glassBackgroundEffect()
            }
            #else
            .inspector(isPresented: $showsInspector) {
                Form {
                    controls
                }
                .formStyle(.grouped)
                .inspectorColumnWidth(280)
            }
            #endif
            .toolbar {
                Toggle(isOn: $showsInspector) {
                    Label("Controls", systemImage: "sidebar.right")
                }
            }
    }
}
