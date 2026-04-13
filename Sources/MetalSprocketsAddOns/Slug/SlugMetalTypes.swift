@preconcurrency import Metal
import MetalSprocketsAddOnsShaders
import simd

// MARK: - View Constants

/// Per-frame constants passed to the Slug vertex shader.
/// Layout matches SlugViewConstants in SlugShaderTypes.h.
public typealias SlugFrameConstants = SlugViewConstants

extension SlugFrameConstants {
    public init(viewProjectionMatrix: float4x4, viewportSize: SIMD2<Float>) {
        self.init(viewProjectionMatrix: viewProjectionMatrix, viewportSize: viewportSize, _padding: .zero)
    }

    public init(viewProjectionMatrix: float4x4, viewportSize: CGSize) {
        self.init(
            viewProjectionMatrix: viewProjectionMatrix,
            viewportSize: SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height)),
            _padding: .zero
        )
    }
}

// MARK: - Glyph Vertex

/// Vertex data for a single glyph quad corner.
/// Layout matches SlugVertexData in SlugShaderTypes.h.
public typealias GlyphVertex = SlugVertexData

extension GlyphVertex {
    static let descriptor: MTLVertexDescriptor = {
        let desc = MTLVertexDescriptor()

        // 5 float4 attributes
        for i in 0 ..< 5 {
            desc.attributes[i].format = .float4
            desc.attributes[i].offset = i * 16
            desc.attributes[i].bufferIndex = 0
        }

        // indices: uint2 at offset 80
        desc.attributes[5].format = .uint2
        desc.attributes[5].offset = 80
        desc.attributes[5].bufferIndex = 0

        desc.layouts[0].stride = MemoryLayout<Self>.stride
        desc.layouts[0].stepFunction = .perVertex

        return desc
    }()
}
