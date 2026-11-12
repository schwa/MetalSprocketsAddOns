import Metal
import MetalSprockets
import MetalSprocketsAddOnsShaders
import simd

/// Draws an offscreen layered scene, one array slice per view, into the current render pass's views, with its depth.
///
/// Use it to show work that must happen offscreen before it can be displayed, such as a shadowed scene from a
/// layered ``ShadowContext``, in a pass whose attachments can't be written from compute (for example a visionOS
/// compositor pass). Slice `i` goes to view `i`'s render target slice and viewport, so it works for layered and
/// side-by-side layouts. Pixels whose depth is `clearDepth` are not drawn.
///
/// Each slice must be the size of its view's viewport.
public struct LayeredCompositeRenderPipeline: Element {
    let color: MTLTexture
    let depth: MTLTexture
    let views: StereoViews
    let clearDepth: Float
    let depthCompareFunction: MTLCompareFunction

    @MSState
    private var vertexShader = ShaderLibrary.module.namespaced("LayeredComposite").requiredFunction(named: "vertex_main", type: VertexShader.self)

    @MSState
    private var fragmentShader = ShaderLibrary.module.namespaced("LayeredComposite").requiredFunction(named: "fragment_main", type: FragmentShader.self)

    /// - Parameters:
    ///   - color: A 2D array colour texture with a slice per view.
    ///   - depth: A 2D array depth texture with a slice per view.
    ///   - clearDepth: The value `depth` was cleared to: 0 with reverse Z, 1 otherwise.
    ///   - depthCompareFunction: The depth test against the pass. `.greater` for reverse Z.
    public init(color: MTLTexture, depth: MTLTexture, views: StereoViews, clearDepth: Float = 0, depthCompareFunction: MTLCompareFunction = .greater) throws {
        try ShadowContext.validateLayered(views: views, textures: [color, depth])
        self.color = color
        self.depth = depth
        self.views = views
        self.clearDepth = clearDepth
        self.depthCompareFunction = depthCompareFunction
    }

    public var body: some Element {
        get throws {
            let views = views
            try RenderPipeline(label: "Layered Composite", vertexShader: vertexShader, fragmentShader: fragmentShader) {
                ForEach(Array(views.viewports.enumerated()), id: \.offset) { index, viewport in
                    let view = LayeredCompositeView(
                        viewportOrigin: views.isStereo ? SIMD2(Float(viewport.originX), Float(viewport.originY)) : .zero,
                        viewIndex: UInt32(index),
                        clearDepth: clearDepth
                    )
                    Draw { encoder in
                        views.setViewports(encoder)
                        encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
                    }
                    .parameter("view", functionType: .vertex, value: view)
                    .parameter("view", functionType: .fragment, value: view)
                    .parameter("color", texture: color)
                    .parameter("depth", texture: depth)
                }
            }
            .depthCompare(function: depthCompareFunction, writes: true)
            // Writing the render target array index needs a declared primitive topology.
            .renderPipelineDescriptorTransformer { descriptor in
                descriptor.inputPrimitiveTopology = .triangle
            }
        }
    }
}
