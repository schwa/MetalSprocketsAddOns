import MetalSprocketsUI
import SwiftUI

/// Overlays MetalSprockets' `FrameTimingView` on any `RenderView` in the content.
///
/// `onFrameTimingChange` reaches every `RenderView` below it through the environment. Statistics
/// arrive every frame, so they live in an observable model that only the HUD reads; the demo
/// content is not invalidated per frame.
struct FrameRateHUDModifier: ViewModifier {
    @State private var model = FrameRateHUDModel()

    func body(content: Content) -> some View {
        content
            .onFrameTimingChange { statistics in
                model.statistics = statistics
            }
            .overlay(alignment: .topLeading) {
                FrameRateHUDView(model: model)
                    .padding()
            }
    }
}

@Observable
private final class FrameRateHUDModel {
    var statistics: FrameTimingStatistics?
}

private struct FrameRateHUDView: View {
    let model: FrameRateHUDModel

    var body: some View {
        if let statistics = model.statistics {
            FrameTimingView(statistics: statistics, options: [.fps, .frameTime, .gpuTime])
                .allowsHitTesting(false)
        }
    }
}
