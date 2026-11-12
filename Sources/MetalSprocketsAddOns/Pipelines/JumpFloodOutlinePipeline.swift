import Metal
import MetalSprockets
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import simd

// Jump flood outlines, after https://bgolus.medium.com/the-quest-for-very-wide-outlines-ba82ed442cd9
//
// Usage:
//
// ```swift
// Group {
//     RenderPass { SilhouetteMaskRenderPipeline(...) }  // writes mask
//     JumpFloodPipeline(mask: mask, seeds: seeds, maximumDistance: width)
//     RenderPass { JumpFloodOutlineRenderPipeline(mask: mask, seeds: seeds, color: color, width: width) }
// }
// ```

/// Runs the jump flood compute passes. Writes, for each pixel, the position of the nearest masked pixel to `seeds`.
///
/// Place it as a sibling of other passes, like `GaussianBlurPipeline`. Pixels farther than `maximumDistance` from the
/// mask may not find their nearest seed.
///
/// For stereo, use 2D array textures (one slice per eye, e.g. a mask drawn by ``SilhouetteMaskRenderPipeline`` with
/// two views); every slice floods independently.
public struct JumpFloodPipeline: Element {
    let mask: MTLTexture
    let seeds: MTLTexture
    let maximumDistance: Float

    @MSState
    private var initKernel = ShaderLibrary.module.namespaced("JumpFlood").requiredFunction(named: "init_seeds", type: ComputeKernel.self)

    @MSState
    private var floodKernel = ShaderLibrary.module.namespaced("JumpFlood").requiredFunction(named: "flood_step", type: ComputeKernel.self)

    @MSState
    private var initArrayKernel = ShaderLibrary.module.namespaced("JumpFlood").requiredFunction(named: "init_seeds_array", type: ComputeKernel.self)

    @MSState
    private var floodArrayKernel = ShaderLibrary.module.namespaced("JumpFlood").requiredFunction(named: "flood_step_array", type: ComputeKernel.self)

    @MSState
    private var pingPongCache = SeedTextureCache()

    /// - Parameters:
    ///   - mask: Values >= 0.5 are inside. Must have `.shaderRead` usage.
    ///   - seeds: Output. Use ``makeSeedTexture(device:width:height:arrayLength:)``, sized like `mask`.
    ///   - maximumDistance: Largest distance, in pixels, the flood must reach. Usually the outline width.
    public init(mask: MTLTexture, seeds: MTLTexture, maximumDistance: Float) {
        self.mask = mask
        self.seeds = seeds
        self.maximumDistance = maximumDistance
    }

    /// With an `arrayLength` (for stereo, 2), a 2D array texture to match an array mask.
    public static func makeSeedTexture(device: MTLDevice, width: Int, height: Int, arrayLength: Int? = nil) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg32Float, width: width, height: height, mipmapped: false)
        if let arrayLength {
            descriptor.textureType = .type2DArray
            descriptor.arrayLength = arrayLength
        }
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        let texture = try device.makeTexture(descriptor: descriptor)
            .orThrow(.resourceCreationFailure("Failed to create jump flood seed texture"))
        texture.label = "JumpFlood Seeds"
        return texture
    }

    /// Jump sizes, largest first: 2^(n-1) ... 1, with 2^n >= maximumDistance + 1.
    static func stepSizes(maximumDistance: Float) -> [Int32] {
        let count = max(Int(ceil(log2(max(maximumDistance, 1) + 1))), 1)
        return (0..<count).reversed().map { Int32(1) << Int32($0) }
    }

    public var body: some Element {
        get throws {
            let pingPong = try pingPongCache.texture(matching: seeds)
            let isArray = seeds.textureType == .type2DArray
            let initKernel = isArray ? initArrayKernel : initKernel
            let floodKernel = isArray ? floodArrayKernel : floodKernel
            let threadsPerGrid = MTLSize(width: seeds.width, height: seeds.height, depth: isArray ? seeds.arrayLength : 1)
            let threadsPerThreadgroup = MTLSize(width: 8, height: 8, depth: 1)
            let steps = Self.stepSizes(maximumDistance: maximumDistance)

            try ComputePass(label: "JumpFlood") {
                // Wait for earlier work that writes `mask`.
                QueueBarrier(after: [.vertex, .fragment, .dispatch, .blit], before: .dispatch)
                try ComputePipeline(label: "JumpFloodInit", computeKernel: initKernel) {
                    try ComputeDispatch(threadsPerGrid: threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                        .parameter("mask", texture: mask)
                        .parameter("seeds", texture: seeds)
                }
                EncoderBarrier(after: .dispatch, before: .dispatch)
                try ComputePipeline(label: "JumpFloodStep", computeKernel: floodKernel) {
                    // Each step floods along x into the ping-pong texture, then along y back into `seeds`.
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                        try ComputeDispatch(threadsPerGrid: threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                            .parameter("source", texture: seeds)
                            .parameter("destination", texture: pingPong)
                            .parameter("params", value: JumpFloodStepParameters(offset: [step, 0]))
                        EncoderBarrier(after: .dispatch, before: .dispatch)
                        try ComputeDispatch(threadsPerGrid: threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                            .parameter("source", texture: pingPong)
                            .parameter("destination", texture: seeds)
                            .parameter("params", value: JumpFloodStepParameters(offset: [0, step]))
                        EncoderBarrier(after: .dispatch, before: .dispatch)
                    }
                }
            }
            // The outline render pass reads `seeds`.
            .barrierAfterPass(after: .dispatch, beforeQueueStages: [.fragment])
        }
    }
}

/// Draws an anti-aliased outline of `width` pixels around the mask, using seeds from ``JumpFloodPipeline``.
///
/// Put it in a `RenderPass` whose color attachment is the same size as `mask`. It alpha-blends over the target and
/// leaves pixels inside the mask unchanged.
///
/// For stereo, pass 2D array `mask` and `seeds` (one slice per eye) and the `views` the pass draws, whose count
/// matches the slices. Each eye reads its own slice.
///
/// Each outline pixel gets the depth of the nearest masked pixel, read from the mask's green channel (see
/// ``SilhouetteMaskRenderPipeline``). With the default `.always`, the outline draws over everything (x-ray). Pass
/// `.lessEqual` (`.greaterEqual` with reverse Z) and attach the scene depth to hide the outline behind objects in
/// front of the masked object.
public struct JumpFloodOutlineRenderPipeline: Element {
    let mask: MTLTexture
    let seeds: MTLTexture
    let color: SIMD4<Float>
    let width: Float
    let depthCompareFunction: MTLCompareFunction
    let writesDepth: Bool
    let views: StereoViews?

    @MSState
    private var vertexShader = ShaderLibrary.module.namespaced("JumpFlood").requiredFunction(named: "outline_vertex", type: VertexShader.self)

    @MSState
    private var fragmentShader = ShaderLibrary.module.namespaced("JumpFlood").requiredFunction(named: "outline_fragment", type: FragmentShader.self)

    @MSState
    private var arrayFragmentShader = ShaderLibrary.module.namespaced("JumpFlood").requiredFunction(named: "outline_fragment_array", type: FragmentShader.self)

    /// `writesDepth` writes the outline's depth (the nearest masked pixel's), e.g. for visionOS, which shows color only
    /// where depth is written.
    public init(mask: MTLTexture, seeds: MTLTexture, color: SIMD4<Float>, width: Float, depthCompareFunction: MTLCompareFunction = .always, writesDepth: Bool = false, views: StereoViews? = nil) {
        precondition((mask.textureType == .type2DArray) == (seeds.textureType == .type2DArray), "mask and seeds must both be 2D or both be 2D arrays")
        self.views = views
        self.writesDepth = writesDepth
        self.mask = mask
        self.seeds = seeds
        self.color = color
        self.width = width
        self.depthCompareFunction = depthCompareFunction
    }

    public var body: some Element {
        get throws {
            // Widths under one pixel fade the alpha instead of thinning the line.
            let parameters = JumpFloodOutlineParameters(color: [color.x, color.y, color.z, color.w * min(max(width, 0), 1)], width: max(width, 1))
            let isArray = mask.textureType == .type2DArray
            try RenderPipeline(label: "JumpFloodOutline", vertexShader: vertexShader, fragmentShader: isArray ? arrayFragmentShader : fragmentShader) {
                Draw { [views] encoder in
                    views?.configure(encoder)
                    encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
                }
                .parameter("mask", texture: mask)
                .parameter("seeds", texture: seeds)
                .parameter("params", functionType: .fragment, value: parameters)
            }
            .depthCompare(function: depthCompareFunction, writes: writesDepth)
            .renderPipelineDescriptorTransformer { [viewCount = views?.count ?? 1] descriptor in
                descriptor.maxVertexAmplificationCount = viewCount
                guard let attachment = descriptor.colorAttachments[0] else {
                    return
                }
                attachment.blendingState = .enabled
                attachment.rgbBlendOperation = .add
                attachment.alphaBlendOperation = .add
                attachment.sourceRGBBlendFactor = .sourceAlpha
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
        }
    }
}

private final class SeedTextureCache {
    private var texture: MTLTexture?

    func texture(matching seeds: MTLTexture) throws -> MTLTexture {
        if let texture, texture.width == seeds.width, texture.height == seeds.height, texture.textureType == seeds.textureType, texture.arrayLength == seeds.arrayLength, texture.device === seeds.device {
            return texture
        }
        let arrayLength = seeds.textureType == .type2DArray ? seeds.arrayLength : nil
        let texture = try JumpFloodPipeline.makeSeedTexture(device: seeds.device, width: seeds.width, height: seeds.height, arrayLength: arrayLength)
        texture.label = "JumpFlood PingPong"
        self.texture = texture
        return texture
    }
}
