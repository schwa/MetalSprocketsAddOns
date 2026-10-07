import SwiftUI

/// Sidebar of demos plus the selected demo's render surface.
public struct DemoBrowserView: View {
    @State private var selection: Demo?

    public init() {
        // Nothing to configure.
    }

    public var body: some View {
        NavigationSplitView {
            List(Demo.all, selection: $selection) { demo in
                NavigationLink(value: demo) {
                    Label {
                        VStack(alignment: .leading) {
                            Text(demo.name)
                            Text(demo.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: demo.systemImage)
                    }
                }
            }
            .navigationTitle("Add-Ons")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if let demo = selection {
                DemoView(demo: demo)
                    .navigationTitle(demo.name)
                    // Demos own GPU resources keyed to their identity; rebuild on switch.
                    .id(demo.id)
            } else {
                ContentUnavailableView("Pick a Demo", systemImage: "sidebar.left")
            }
        }
    }
}

#Preview {
    DemoBrowserView()
}
