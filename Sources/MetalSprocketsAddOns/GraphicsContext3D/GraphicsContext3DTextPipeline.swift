#if arch(arm64)

import CoreGraphics
import CoreText
import Foundation
import Metal
import MetalSprockets
import simd

/// Renders the text labels recorded by a ``GraphicsContext3D`` using Slug.
///
/// Labels are laid out in pixel space and positioned by projecting their world-space anchor
/// into the viewport, so they keep a constant on-screen size. The Slug pipeline neither
/// depth-tests nor writes depth, so labels sit on top of the context's strokes and fills.
///
/// With two views, each label is a world-space billboard at its anchor, sized and turned to face the first view, so
/// each eye sees it at its own position.
internal struct GraphicsContext3DTextPipeline: Element {
    let labels: [GraphicsContext3D.TextLabel]
    let views: StereoViews
    let viewport: SIMD2<Float>
    var viewProjection: float4x4 { views.viewProjections[0] }

    @MSState
    private var scene: SlugScene?

    @MSState
    private var sceneLabels: [GraphicsContext3D.TextLabel] = []

    @MSState
    private var fontAtlasCache: FontAtlasCache?

    @MSEnvironment(\.device)
    private var device

    init(labels: [GraphicsContext3D.TextLabel], views: StereoViews, viewport: SIMD2<Float>) {
        self.labels = labels
        self.views = views
        self.viewport = viewport
    }

    var body: some Element {
        get throws {
            if let device, scene == nil || sceneLabels != labels {
                let builder = fontAtlasCache.map { SlugTextMeshBuilder(device: device, fontAtlasCache: $0) }
                    ?? SlugTextMeshBuilder(device: device)
                for label in labels {
                    builder.buildMesh(attributedString: label.attributedString)
                }
                fontAtlasCache = builder.sharedFontAtlasCache
                scene = try builder.finalize()
                sceneLabels = labels
            }

            let hasViewport = viewport.x > 0 && viewport.y > 0
            let renderableScene = hasViewport ? scene.flatMap { $0.meshCount > 0 ? $0 : nil } : nil
            if let renderableScene {
                if views.isStereo {
                    updateBillboardMatrices(of: renderableScene)
                } else {
                    updateModelMatrices(of: renderableScene)
                }
            }
            let viewConstants = views.isStereo
                ? views.viewProjections.map { SlugFrameConstants(viewProjectionMatrix: $0, viewportSize: viewport) }
                : [SlugFrameConstants(viewProjectionMatrix: pixelSpaceViewProjection, viewportSize: viewport)]

            return try Group {
                if let renderableScene {
                    try SlugTextRenderPipeline(scene: renderableScene, viewConstants: viewConstants, viewports: views.isStereo ? views.viewports : nil)
                }
            }
        }
    }

    /// Maps pixel offsets from the centre of the viewport to clip space.
    private var pixelSpaceViewProjection: float4x4 {
        float4x4(diagonal: SIMD4<Float>(2 / viewport.x, 2 / viewport.y, 1, 1))
    }

    /// Positions each label's mesh so its centre lands on the projected anchor position.
    private func updateModelMatrices(of scene: SlugScene) {
        scene.withModelMatrices { matrices in
            for (index, label) in labels.enumerated() where index < matrices.count {
                let clipPosition = viewProjection * SIMD4<Float>(label.position, 1)
                guard clipPosition.w > 1e-6 else {
                    // Behind (or on) the camera plane: collapse the mesh so it draws nothing.
                    matrices[index] = float4x4(diagonal: SIMD4<Float>(0, 0, 0, 1))
                    continue
                }
                let screenPosition = SIMD2<Float>(
                    clipPosition.x / clipPosition.w * viewport.x / 2,
                    clipPosition.y / clipPosition.w * viewport.y / 2
                )
                let bounds = scene.meshes[index].bounds
                matrices[index] = float4x4(translation: SIMD3<Float>(
                    screenPosition.x - Float(bounds.midX),
                    screenPosition.y - Float(bounds.midY),
                    0
                ))
            }
        }
    }
}

extension GraphicsContext3DTextPipeline {
    /// Places each label's mesh in world space at its anchor, facing the first view, with one glyph unit (pixel) per
    /// pixel of that view at the anchor's depth.
    private func updateBillboardMatrices(of scene: SlugScene) {
        let inverseViewProjection = viewProjection.inverse
        func unproject(_ ndc: SIMD3<Float>) -> SIMD3<Float> {
            let world = inverseViewProjection * SIMD4<Float>(ndc, 1)
            return SIMD3<Float>(world.x, world.y, world.z) / world.w
        }
        scene.withModelMatrices { matrices in
            for (index, label) in labels.enumerated() where index < matrices.count {
                let clipPosition = viewProjection * SIMD4<Float>(label.position, 1)
                guard clipPosition.w > 1e-6 else {
                    // Behind (or on) the camera plane: collapse the mesh so it draws nothing.
                    matrices[index] = float4x4(diagonal: SIMD4<Float>(0, 0, 0, 1))
                    continue
                }
                let ndc = SIMD3<Float>(clipPosition.x, clipPosition.y, clipPosition.z) / clipPosition.w
                let anchor = unproject(ndc)
                let xAxis = unproject(ndc + [2 / viewport.x, 0, 0]) - anchor
                let yAxis = unproject(ndc + [0, 2 / viewport.y, 0]) - anchor
                let bounds = scene.meshes[index].bounds
                let origin = anchor - xAxis * Float(bounds.midX) - yAxis * Float(bounds.midY)
                // Glyphs are flat (z = 0), so the third column only needs to be independent of the others.
                matrices[index] = float4x4(columns: (
                    SIMD4<Float>(xAxis, 0),
                    SIMD4<Float>(yAxis, 0),
                    SIMD4<Float>(simd_cross(xAxis, yAxis), 0),
                    SIMD4<Float>(origin, 1)
                ))
            }
        }
    }
}

private extension GraphicsContext3D.TextLabel {
    var attributedString: NSAttributedString {
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        let cgColor = CGColor(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: CGFloat(color.w))
        return NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: cgColor])
    }
}

#endif // arch(arm64)
