import Metal
import MetalSprockets
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport

// MARK: - FastBlurPipeline

/// A Gaussian blur whose cost does not grow with the radius, so the radius can be large and animated smoothly.
///
/// The image is box-downsampled, blurred with a small separable Gaussian, and upsampled again. The variance added by the
/// down- and upsampling is subtracted from the working sigma, so the result stays close to a true Gaussian of `sigma`
/// and changes smoothly when the downsample factor changes. Edges are clamped.
///
/// Based on Aras Pranckevičius, "Fast blur with animated radius" (2026).
///
/// Place it as a sibling of other passes, like `GaussianBlurPipeline`. `source` and `destination` may be the same texture.
public struct FastBlurPipeline: Element {
    let source: MTLTexture
    let destination: MTLTexture
    let sigma: SIMD2<Float>

    @MSState
    private var downsampleKernel = ShaderLibrary.module.namespaced("GaussianBlur").requiredFunction(named: "fast_blur_downsample", type: ComputeKernel.self)

    @MSState
    private var blurKernel = ShaderLibrary.module.namespaced("GaussianBlur").requiredFunction(named: "blur_pass", type: ComputeKernel.self)

    @MSState
    private var upsampleKernel = ShaderLibrary.module.namespaced("GaussianBlur").requiredFunction(named: "fast_blur_upsample", type: ComputeKernel.self)

    @MSState
    private var textureCache = FastBlurTextureCache()

    /// - Parameters:
    ///   - source: The input texture. Must have `.shaderRead` usage.
    ///   - destination: The output texture, same size as `source`. Must have `.shaderWrite` usage.
    ///   - sigma: The standard deviation of the Gaussian in pixels, per axis. Values below zero are treated as zero.
    public init(source: MTLTexture, destination: MTLTexture, sigma: SIMD2<Float>) {
        self.source = source
        self.destination = destination
        self.sigma = sigma
    }

    public init(source: MTLTexture, destination: MTLTexture, sigma: Float) {
        self.init(source: source, destination: destination, sigma: SIMD2(repeating: sigma))
    }

    public var body: some Element {
        get throws {
            let planX = Self.plan(sigma: sigma.x, size: destination.width)
            let planY = Self.plan(sigma: sigma.y, size: destination.height)
            let width = destination.width
            let height = destination.height
            let lowWidth = (width + planX.factor - 1) / planX.factor
            let lowHeight = (height + planY.factor - 1) / planY.factor

            let shrunkX = try textureCache.texture(named: "ShrunkX", width: lowWidth, height: height, device: destination.device)
            let low = try textureCache.texture(named: "Low", width: lowWidth, height: lowHeight, device: destination.device)
            let lowBlurredX = try textureCache.texture(named: "LowBlurredX", width: lowWidth, height: lowHeight, device: destination.device)
            let lowBlurred = try textureCache.texture(named: "LowBlurred", width: lowWidth, height: lowHeight, device: destination.device)

            let weightsX = Self.weights(sigma: planX.workingSigma)
            let weightsY = Self.weights(sigma: planY.workingSigma)
            let threadsPerThreadgroup = MTLSize(width: 8, height: 8, depth: 1)
            let lowGrid = MTLSize(width: lowWidth, height: lowHeight, depth: 1)

            try ComputePass(label: "FastBlur") {
                QueueBarrier(after: [.vertex, .fragment, .dispatch, .blit], before: .dispatch)
                try ComputePipeline(label: "FastBlur Downsample", computeKernel: downsampleKernel) {
                    try ComputeDispatch(threadsPerGrid: MTLSize(width: lowWidth, height: height, depth: 1), threadsPerThreadgroup: threadsPerThreadgroup)
                        .parameter("source", texture: source)
                        .parameter("destination", texture: shrunkX)
                        .parameter("params", value: FastBlurDownsampleParameters(direction: [1, 0], factor: Int32(planX.factor)))
                    EncoderBarrier(after: .dispatch, before: .dispatch)
                    try ComputeDispatch(threadsPerGrid: lowGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                        .parameter("source", texture: shrunkX)
                        .parameter("destination", texture: low)
                        .parameter("params", value: FastBlurDownsampleParameters(direction: [0, 1], factor: Int32(planY.factor)))
                }
                EncoderBarrier(after: .dispatch, before: .dispatch)
                try ComputePipeline(label: "FastBlur Blur", computeKernel: blurKernel) {
                    try ComputeDispatch(threadsPerGrid: lowGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                        .parameter("source", texture: low)
                        .parameter("destination", texture: lowBlurredX)
                        .parameter("weights", values: weightsX)
                        .parameter("params", value: GaussianBlurParameters(direction: [1, 0], radius: Int32(weightsX.count - 1), edgeMode: 0))
                    EncoderBarrier(after: .dispatch, before: .dispatch)
                    try ComputeDispatch(threadsPerGrid: lowGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                        .parameter("source", texture: lowBlurredX)
                        .parameter("destination", texture: lowBlurred)
                        .parameter("weights", values: weightsY)
                        .parameter("params", value: GaussianBlurParameters(direction: [0, 1], radius: Int32(weightsY.count - 1), edgeMode: 0))
                }
                EncoderBarrier(after: .dispatch, before: .dispatch)
                try ComputePipeline(label: "FastBlur Upsample", computeKernel: upsampleKernel) {
                    let parameters = FastBlurUpsampleParameters(
                        factor: [Int32(planX.factor), Int32(planY.factor)],
                        bSpline: [planX.bSpline ? 1 : 0, planY.bSpline ? 1 : 0]
                    )
                    try ComputeDispatch(threadsPerGrid: MTLSize(width: width, height: height, depth: 1), threadsPerThreadgroup: threadsPerThreadgroup)
                        .parameter("source", texture: lowBlurred)
                        .parameter("destination", texture: destination)
                        .parameter("params", value: parameters)
                }
            }
        }
    }

    struct AxisPlan: Equatable {
        var factor: Int
        var bSpline: Bool
        /// Sigma of the Gaussian run at low resolution, in low-resolution pixels.
        var workingSigma: Float
    }

    /// The smallest working sigma, in low-resolution pixels, before switching to a smaller downsample factor.
    static let minimumWorkingSigma: Float = 2

    /// Variance, in full-resolution pixels², that reconstruction adds when upsampling by `factor`.
    static func upsampleVariance(factor: Int, bSpline: Bool) -> Float {
        guard factor > 1 else {
            return 0
        }
        let factor = Float(factor)
        return factor * factor * (bSpline ? 1.0 / 3.0 : 1.0 / 6.0)
    }

    static func plan(sigma: Float, size: Int) -> AxisPlan {
        let variance = max(sigma, 0) * max(sigma, 0)
        // Start from an upper bound on the factor, then step down until the working sigma is large enough.
        let bound = (variance + 1.0 / 12.0) / (minimumWorkingSigma * minimumWorkingSigma + 1.0 / 12.0 + 1.0 / 6.0)
        var factor = min(max(Int(bound.squareRoot()), 1), max(size, 1))
        while factor > 1 {
            let bSpline = factor > 2
            let working = workingVariance(variance: variance, factor: factor, bSpline: bSpline)
            if working >= minimumWorkingSigma * minimumWorkingSigma {
                return AxisPlan(factor: factor, bSpline: bSpline, workingSigma: working.squareRoot())
            }
            factor -= 1
        }
        return AxisPlan(factor: 1, bSpline: false, workingSigma: variance.squareRoot())
    }

    static func workingVariance(variance: Float, factor: Int, bSpline: Bool) -> Float {
        let factorSquared = Float(factor * factor)
        let downsampleVariance = (factorSquared - 1) / 12
        return (variance - downsampleVariance - upsampleVariance(factor: factor, bSpline: bSpline)) / factorSquared
    }

    /// Normalized one-sided weights, centre tap first. Tapered to zero between 3σ and 4σ so bright pixels do not show a cut-off.
    static func weights(sigma: Float) -> [Float] {
        guard sigma > 0.01 else {
            return [1]
        }
        let radius = max(Int((4 * sigma).rounded(.up)), 1)
        let raw = (0...radius).map { offset -> Float in
            let distance = Float(offset)
            let gaussian = exp(-distance * distance / (2 * sigma * sigma))
            let t = min(max((distance - 3 * sigma) / sigma, 0), 1)
            let taper = 1 - t * t * (3 - 2 * t)
            return gaussian * taper
        }
        let total = raw[0] + 2 * raw.dropFirst().reduce(0, +)
        return raw.map { $0 / total }
    }
}

private final class FastBlurTextureCache {
    private var textures: [String: MTLTexture] = [:]

    func texture(named name: String, width: Int, height: Int, device: MTLDevice) throws -> MTLTexture {
        if let texture = textures[name], texture.width == width, texture.height == height, texture.device === device {
            return texture
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        let texture = try device.makeTexture(descriptor: descriptor)
            .orThrow(.resourceCreationFailure("Failed to create fast blur intermediate texture"))
        texture.label = "FastBlur \(name)"
        textures[name] = texture
        return texture
    }
}
