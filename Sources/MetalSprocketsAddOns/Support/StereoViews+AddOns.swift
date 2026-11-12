import Metal
import MetalSprocketsAddOnsShaders
import simd

/// Views drawn at once, e.g. the eyes of a visionOS immersive space: per view a view-projection matrix and an
/// optional viewport. Draws are amplified into one stream per view, each routed to its viewport and render target
/// array slice.
public struct StereoViews: Sendable {
    public var viewProjections: [float4x4]
    public var viewports: [MTLViewport]?

    /// One or two views. With `viewports`, one per view.
    public init(viewProjections: [float4x4], viewports: [MTLViewport]? = nil) {
        precondition((1 ... Int(kStereoMaxViewCount)).contains(viewProjections.count), "One or two views")
        precondition(viewports.map { $0.count == viewProjections.count } ?? true, "One viewport per view")
        self.viewProjections = viewProjections
        self.viewports = viewports
    }

    public init(viewProjection: float4x4) {
        self.init(viewProjections: [viewProjection])
    }

    public var count: Int { viewProjections.count }

    var isStereo: Bool { count > 1 }

    /// Per-view values for the shaders' fixed-size per-view arrays. With one view, the second repeats the first.
    var viewProjectionPair: (float4x4, float4x4) {
        (viewProjections[0], viewProjections[count > 1 ? 1 : 0])
    }

    /// Amplifies the following draws into one stream per view. Draws reset amplification, so every draw calls this,
    /// including draws you write inside a pipeline that takes `StereoViews` (e.g. ``DebugRenderPipeline``).
    public func configure(_ encoder: any MTL4RenderCommandEncoder) {
        guard isStereo else {
            return
        }
        let mappings = (0 ..< count).map { MTLVertexAmplificationViewMapping(viewportArrayIndexOffset: UInt32($0), renderTargetArrayIndexOffset: UInt32($0)) }
        encoder.setVertexAmplificationCount(mappings)
        setViewports(encoder)
    }

    func setViewports(_ encoder: any MTL4RenderCommandEncoder) {
        if let viewports {
            encoder.setViewports(viewports)
        }
    }
}
