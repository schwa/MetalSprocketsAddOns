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
public struct JumpFloodPipeline: Element {
    let mask: MTLTexture
    let seeds: MTLTexture
    let maximumDistance: Float

    @MSState
    private var initKernel = ShaderLibrary.module.namespaced("JumpFlood").requiredFunction(named: "init_seeds", type: ComputeKernel.self)

    @MSState
    private var floodKernel = ShaderLibrary.module.namespaced("JumpFlood").requiredFunction(named: "flood_step", type: ComputeKernel.self)

    @MSState
    private var pingPongCache = SeedTextureCache()

    /// - Parameters:
    ///   - mask: Values >= 0.5 are inside. Must have `.shaderRead` usage.
    ///   - seeds: Output. Use ``makeSeedTexture(device:width:height:)``, sized like `mask`.
    ///   - maximumDistance: Largest distance, in pixels, the flood must reach. Usually the outline width.
    public init(mask: MTLTexture, seeds: MTLTexture, maximumDistance: Float) {
        self.mask = mask
        self.seeds = seeds
        self.maximumDistance = maximumDistance
    }

    public static func makeSeedTexture(device: MTLDevice, width: Int, height: Int) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg32Float, width: width, height: height, mipmapped: false)
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
            let threadsPerGrid = MTLSize(width: seeds.width, height: seeds.height, depth: 1)
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

    @MSState
    private var vertexShader = ShaderLibrary.module.namespaced("JumpFlood").requiredFunction(named: "outline_vertex", type: VertexShader.self)

    @MSState
    private var fragmentShader = ShaderLibrary.module.namespaced("JumpFlood").requiredFunction(named: "outline_fragment", type: FragmentShader.self)

    public init(mask: MTLTexture, seeds: MTLTexture, color: SIMD4<Float>, width: Float, depthCompareFunction: MTLCompareFunction = .always) {
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
            try RenderPipeline(label: "JumpFloodOutline", vertexShader: vertexShader, fragmentShader: fragmentShader) {
                Draw { encoder in
                    encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
                }
                .parameter("mask", texture: mask)
                .parameter("seeds", texture: seeds)
                .parameter("params", functionType: .fragment, value: parameters)
            }
            .depthCompare(function: depthCompareFunction, writes: false)
            .renderPipelineDescriptorTransformer { descriptor in
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
        if let texture, texture.width == seeds.width, texture.height == seeds.height, texture.device === seeds.device {
            return texture
        }
        let texture = try JumpFloodPipeline.makeSeedTexture(device: seeds.device, width: seeds.width, height: seeds.height)
        texture.label = "JumpFlood PingPong"
        self.texture = texture
        return texture
    }
}
