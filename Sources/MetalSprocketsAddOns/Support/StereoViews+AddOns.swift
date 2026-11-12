import Metal
import MetalSprockets
import MetalSprocketsAddOnsShaders
import simd

extension StereoViews {
    /// One view with an already combined view-projection matrix. The viewport is unused: one view never sets viewports.
    init(viewProjection: float4x4) {
        self.init(viewMatrices: [matrix_identity_float4x4], projectionMatrices: [viewProjection], viewports: [MTLViewport()])
    }

    /// Per-view values for the shaders' fixed-size per-view arrays. With one view, the second repeats the first.
    var viewProjectionPair: (float4x4, float4x4) {
        let viewProjections = viewProjections
        return (viewProjections[0], viewProjections[isStereo ? 1 : 0])
    }

    /// Sets the per-view viewports for draws that amplify themselves (e.g. mesh shaders). Does nothing for one view.
    func setViewports(_ encoder: any MTL4RenderCommandEncoder) {
        if isStereo {
            encoder.setViewports(viewports)
        }
    }
}
