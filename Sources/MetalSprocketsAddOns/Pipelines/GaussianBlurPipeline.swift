#if canImport(MetalPerformanceShaders)
import Metal
import MetalPerformanceShaders
import MetalSprockets
import MetalSprocketsSupport

// MARK: - GaussianBlurPipeline

/// A MetalSprockets-style wrapper around `MPSImageGaussianBlur`.
///
/// `GaussianBlurPipeline` performs a two-pass separable Gaussian blur using Apple's
/// vendor-optimized `MetalPerformanceShaders` kernel. Place it inside a
/// `CommandBufferElement` (i.e. outside of any `RenderPass` or `ComputePass`):
/// MPS encodes directly onto the command buffer and manages its own encoders
/// internally.
///
/// ## Example
///
/// ```swift
/// CommandBufferElement {
///     GaussianBlurPipeline(source: sourceTexture, destination: blurredTexture, sigma: 4.0)
/// }
/// ```
///
/// ## Intermediate texture
///
/// MPS allocates and manages its own intermediate storage during the two-pass
/// encode — no intermediate texture needs to be supplied. If `source` and
/// `destination` refer to the same texture, MPS will allocate a temporary copy
/// automatically.
public struct GaussianBlurPipeline: Element {
    let source: MTLTexture
    let destination: MTLTexture
    let sigma: Float
    let edgeMode: MPSImageEdgeMode

    @MSState
    private var kernel: MPSImageGaussianBlur?

    /// Creates a Gaussian blur pipeline.
    ///
    /// - Parameters:
    ///   - source: The input texture. Must have `.shaderRead` usage.
    ///   - destination: The output texture. Must have `.shaderWrite` usage and
    ///     match `source`'s pixel format.
    ///   - sigma: The standard deviation of the Gaussian kernel, in pixels.
    ///     Larger values produce a wider blur. Must be positive.
    ///   - edgeMode: How samples outside the texture are handled. Defaults to
    ///     `.clamp`.
    public init(
        source: MTLTexture,
        destination: MTLTexture,
        sigma: Float,
        edgeMode: MPSImageEdgeMode = .clamp
    ) {
        self.source = source
        self.destination = destination
        self.sigma = sigma
        self.edgeMode = edgeMode
    }

    public var body: some Element {
        EmptyElement()
            .onWorkloadEnter { environmentValues in
                let commandBuffer = try environmentValues.commandBuffer
                    .orThrow(.missingEnvironment(\.commandBuffer))

                // Create or reuse the MPS kernel. Sigma is captured at
                // construction time, so we must recreate the kernel if sigma
                // changes between frames.
                let resolvedKernel: MPSImageGaussianBlur
                if let existing = kernel, existing.sigma == sigma {
                    resolvedKernel = existing
                } else {
                    resolvedKernel = MPSImageGaussianBlur(device: commandBuffer.device, sigma: sigma)
                    kernel = resolvedKernel
                }
                resolvedKernel.edgeMode = edgeMode
                resolvedKernel.encode(
                    commandBuffer: commandBuffer,
                    sourceTexture: source,
                    destinationTexture: destination
                )
            }
    }
}
#endif
