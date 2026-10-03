import Metal
import MetalSprockets
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport

// MARK: - GaussianBlurPipeline

/// A two-pass separable Gaussian blur that runs as its own compute pass.
///
/// Place it as a sibling of other passes, not inside a `RenderPass` or `ComputePass`:
///
/// ```swift
/// Group {
///     RenderPass { ... }  // writes sourceTexture
///     GaussianBlurPipeline(source: sourceTexture, destination: blurredTexture, sigma: 4.0)
/// }
/// ```
///
/// `source` and `destination` may be the same texture; the blur goes through an internal intermediate texture.
public struct GaussianBlurPipeline: Element {
    public enum EdgeMode: Int32, Sendable {
        /// Samples outside the texture use the nearest edge pixel.
        case clamp = 0
        /// Samples outside the texture are zero.
        case zero = 1
    }

    let source: MTLTexture
    let destination: MTLTexture
    let sigma: Float
    let edgeMode: EdgeMode

    @MSState
    private var computeKernel = ShaderLibrary.module.namespaced("GaussianBlur").requiredFunction(named: "blur_pass", type: ComputeKernel.self)

    @MSState
    private var intermediateCache = IntermediateTextureCache()

    /// Creates a Gaussian blur pipeline.
    ///
    /// - Parameters:
    ///   - source: The input texture. Must have `.shaderRead` usage.
    ///   - destination: The output texture. Must have `.shaderWrite` usage.
    ///   - sigma: The standard deviation of the Gaussian kernel, in pixels. Must be positive.
    ///   - edgeMode: How samples outside the texture are handled.
    public init(source: MTLTexture, destination: MTLTexture, sigma: Float, edgeMode: EdgeMode = .clamp) {
        self.source = source
        self.destination = destination
        self.sigma = sigma
        self.edgeMode = edgeMode
    }

    public var body: some Element {
        get throws {
            let weights = Self.weights(sigma: sigma)
            let radius = Int32(weights.count - 1)
            let intermediate = try intermediateCache.texture(matching: destination)
            let threadsPerGrid = MTLSize(width: destination.width, height: destination.height, depth: 1)
            let threadsPerThreadgroup = MTLSize(width: 8, height: 8, depth: 1)
            let horizontal = GaussianBlurParameters(direction: [1, 0], radius: radius, edgeMode: edgeMode.rawValue)
            let vertical = GaussianBlurParameters(direction: [0, 1], radius: radius, edgeMode: edgeMode.rawValue)

            try ComputePass(label: "GaussianBlur") {
                // Wait for earlier work that writes `source`.
                QueueBarrier(after: [.vertex, .fragment, .dispatch, .blit], before: .dispatch)
                try ComputePipeline(label: "GaussianBlur", computeKernel: computeKernel) {
                    try ComputeDispatch(threadsPerGrid: threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                        .parameter("source", texture: source)
                        .parameter("destination", texture: intermediate)
                        .parameter("weights", values: weights)
                        .parameter("params", value: horizontal)
                    EncoderBarrier(after: .dispatch, before: .dispatch)
                    try ComputeDispatch(threadsPerGrid: threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                        .parameter("source", texture: intermediate)
                        .parameter("destination", texture: destination)
                        .parameter("weights", values: weights)
                        .parameter("params", value: vertical)
                }
            }
        }
    }

    /// Normalized one-sided weights, centre tap first. The radius covers three standard deviations.
    static func weights(sigma: Float) -> [Float] {
        let sigma = max(sigma, .ulpOfOne)
        let radius = max(Int((3 * sigma).rounded(.up)), 1)
        let raw = (0...radius).map { offset in
            exp(-Float(offset * offset) / (2 * sigma * sigma))
        }
        let total = raw[0] + 2 * raw.dropFirst().reduce(0, +)
        return raw.map { $0 / total }
    }
}

private final class IntermediateTextureCache {
    private var texture: MTLTexture?

    func texture(matching destination: MTLTexture) throws -> MTLTexture {
        if let texture, texture.width == destination.width, texture.height == destination.height, texture.pixelFormat == destination.pixelFormat, texture.device === destination.device {
            return texture
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: destination.pixelFormat, width: destination.width, height: destination.height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        let texture = try destination.device.makeTexture(descriptor: descriptor)
            .orThrow(.resourceCreationFailure("Failed to create Gaussian blur intermediate texture"))
        texture.label = "GaussianBlur Intermediate"
        self.texture = texture
        return texture
    }
}
