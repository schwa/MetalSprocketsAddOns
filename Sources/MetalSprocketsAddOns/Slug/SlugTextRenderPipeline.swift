import Metal
import MetalSprockets
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import simd

/// A MetalSprockets render pipeline for text rendering using the Slug algorithm.
///
/// Renders all meshes in a shared buffer with a single draw call.
/// Each vertex carries a `fontIndex` (for texture lookup) and `modelIndex`
/// (for per-instance model matrix lookup).
public struct SlugTextRenderPipeline: Element {
    /// Matches `FontTextures` in SlugShaders.metal.
    private struct FontTexturesEntry {
        var curveTextureID: MTLResourceID
        var bandTextureID: MTLResourceID
    }

    let scene: SlugScene
    let viewConstants: [SlugFrameConstants]
    let amplificationCount: Int
    let viewports: [MTLViewport]?
    let wireframe: Bool
    let colorPixelFormat: MTLPixelFormat?
    let depthPixelFormat: MTLPixelFormat?
    let reverseZ: Bool
    let fontTextureBuffer: MTLBuffer
    let shaderLibrary: ShaderLibrary

    /// Creates a Slug text rendering element from a scene with a single view.
    public init(
        scene: SlugScene,
        frameConstants: SlugFrameConstants,
        wireframe: Bool = false
    ) throws {
        try self.init(scene: scene, viewConstants: [frameConstants], wireframe: wireframe)
    }

    /// Creates a Slug text rendering element from a scene with multiple views (for amplification).
    public init(
        scene: SlugScene,
        viewConstants: [SlugFrameConstants],
        wireframe: Bool = false,
        viewports: [MTLViewport]? = nil,
        colorPixelFormat: MTLPixelFormat? = nil,
        depthPixelFormat: MTLPixelFormat? = nil,
        reverseZ: Bool = false
    ) throws {
        precondition(!viewConstants.isEmpty, "viewConstants must have at least one entry")
        self.scene = scene
        self.viewConstants = viewConstants
        self.amplificationCount = viewConstants.count
        self.viewports = viewports
        self.wireframe = wireframe
        self.colorPixelFormat = colorPixelFormat
        self.depthPixelFormat = depthPixelFormat
        self.reverseZ = reverseZ
        self.shaderLibrary = try ShaderLibrary(bundle: .metalSprocketsAddOnsShaders())

        // Create font texture entries buffer
        let device = _MTLCreateSystemDefaultDevice()
        let entries = scene.fontTexturePairs.map { pair in
            FontTexturesEntry(
                curveTextureID: pair.curveTexture.gpuResourceID,
                bandTextureID: pair.bandTexture.gpuResourceID
            )
        }
        self.fontTextureBuffer = try entries.withUnsafeBufferPointer { ptr in
            guard let baseAddress = ptr.baseAddress else {
                throw MetalSprocketsError.resourceCreationFailure("Empty font texture entries")
            }
            guard let buffer = device.makeBuffer(bytes: baseAddress, length: ptr.count * MemoryLayout<FontTexturesEntry>.stride, options: .storageModeShared) else {
                throw MetalSprocketsError.resourceCreationFailure("Failed to create font texture buffer")
            }
            return buffer
        }
        fontTextureBuffer.label = "Slug Font Textures"
    }

    public var body: some Element {
        get throws {
            try RenderPipeline(
                label: "SlugText",
                vertexShader: shaderLibrary.slug_vertex,
                fragmentShader: wireframe ? shaderLibrary.slug_wireframe_fragment : shaderLibrary.slug_fragment
            ) {
                Draw { encoder in
                    encoder.setVertexBuffer(scene.bufferStorage.vertexBuffer, offset: 0, index: 0)
                    encoder.setCullMode(.none)

                    // Vertex amplification for stereo rendering
                    if amplificationCount > 1 {
                        var viewMappings = (0..<amplificationCount).map { index in
                            MTLVertexAmplificationViewMapping(
                                viewportArrayIndexOffset: UInt32(index),
                                renderTargetArrayIndexOffset: UInt32(index)
                            )
                        }
                        encoder.setVertexAmplificationCount(amplificationCount, viewMappings: &viewMappings)
                        if let viewports {
                            encoder.setViewports(viewports)
                        }
                    }

                    if wireframe {
                        encoder.setTriangleFillMode(.lines)
                    }

                    // Tell Metal about the textures referenced in argument buffer
                    let allTextures: [MTLResource] = scene.fontTexturePairs.flatMap { pair in
                        [pair.curveTexture as MTLResource, pair.bandTexture as MTLResource]
                    }
                    encoder.useResources(allTextures, usage: .read, stages: .fragment)

                    // Pass view constants array
                    viewConstants.withUnsafeBufferPointer { ptr in
                        guard let baseAddress = ptr.baseAddress else {
                            return
                        }
                        encoder.setVertexBytes(baseAddress, length: ptr.count * MemoryLayout<SlugFrameConstants>.stride, index: 1)
                    }

                    // ONE draw call for everything
                    encoder.drawIndexedPrimitives(
                        type: .triangle,
                        indexCount: scene.totalIndexCount,
                        indexType: .uint32,
                        indexBuffer: scene.bufferStorage.indexBuffer,
                        indexBufferOffset: 0
                    )
                }
                .parameter("modelMatrices", functionType: .vertex, buffer: scene.modelMatricesBuffer)
                .parameter("fonts", functionType: .fragment, buffer: fontTextureBuffer)
            }
            .vertexDescriptor(GlyphVertex.descriptor)
            .depthCompare(function: reverseZ ? .greater : .always, enabled: reverseZ)
            .renderPipelineDescriptorModifier { desc in
                desc.maxVertexAmplificationCount = amplificationCount
                if let colorPixelFormat {
                    desc.colorAttachments[0].pixelFormat = colorPixelFormat
                }
                if let depthPixelFormat {
                    desc.depthAttachmentPixelFormat = depthPixelFormat
                }
                desc.colorAttachments[0].isBlendingEnabled = true
                desc.colorAttachments[0].sourceRGBBlendFactor = .one
                desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                desc.colorAttachments[0].sourceAlphaBlendFactor = .one
                desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
        }
    }
}
