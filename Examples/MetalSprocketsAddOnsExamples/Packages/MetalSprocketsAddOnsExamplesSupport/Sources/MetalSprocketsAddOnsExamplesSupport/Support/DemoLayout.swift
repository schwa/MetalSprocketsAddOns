import SwiftUI

/// Shared chrome for every demo: the render surface fills the window and the demo's
/// controls sit in an inspector so the demos themselves only describe their own knobs.
struct DemoLayout<Content: View, Controls: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var controls: Controls

    @State private var showsInspector = true

    var body: some View {
        content
            .ignoresSafeArea()
            .inspector(isPresented: $showsInspector) {
                Form {
                    controls
                }
                .formStyle(.grouped)
                .inspectorColumnWidth(min: 220, ideal: 280, max: 400)
            }
            .toolbar {
                Toggle(isOn: $showsInspector) {
                    Label("Controls", systemImage: "sidebar.right")
                }
            }
    }
}
