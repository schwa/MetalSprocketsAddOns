import Metal
import MetalSprockets
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import simd

public struct GraphicsContext3DRenderPipeline: Element {
    let context: GraphicsContext3D
    let viewProjection: float4x4
    let viewport: SIMD2<Float>
    let debugWireframe: Bool

    @MSState
    private var objectShader = ShaderLibrary.module.namespaced("GraphicsContext3D").requiredFunction(named: "lineJoinObjectShader", type: ObjectShader.self)

    @MSState
    private var meshShader = ShaderLibrary.module.namespaced("GraphicsContext3D").requiredFunction(named: "lineJoinMeshShader", type: MeshShader.self)

    @MSState
    private var meshFragmentShader = ShaderLibrary.module.namespaced("GraphicsContext3D").requiredFunction(named: "fragmentShader", type: FragmentShader.self)

    @MSState
    private var fillVertexShader = ShaderLibrary.module.namespaced("GraphicsContext3D").requiredFunction(named: "vertexShader", type: VertexShader.self)

    @MSState
    private var fillFragmentShader = ShaderLibrary.module.namespaced("GraphicsContext3D").requiredFunction(named: "fragmentShader", type: FragmentShader.self)

    // Replaced (never rewritten) on regeneration, so in-flight frames keep reading their own copy.
    @MSState
    var joinDataBuffer: MTLBuffer?

    @MSState
    var fillVertexBuffer: MTLBuffer?

    @MSState
    var previousContext: GraphicsContext3D?

    @MSState
    var contextHasCurves = false

    @MSState
    var previousViewProjection: float4x4?

    @MSState
    var previousViewport: SIMD2<Float>?

    @MSState
    var joinCount: Int = 0

    @MSState
    var fillVertexCount: Int = 0

    @MSEnvironment(\.device)
    var device

    public init(context: GraphicsContext3D, viewProjection: float4x4, viewport: SIMD2<Float>, debugWireframe: Bool = false) {
        self.context = context
        self.viewProjection = viewProjection
        self.viewport = viewport
        self.debugWireframe = debugWireframe
    }

    public var body: some Element {
        get throws {
            guard let device else {
                throw MetalSprocketsError.resourceCreationFailure("No Metal device in environment")
            }

            // Join data and fill vertices are world space; only curve tessellation depends on the camera.
            let hasValidViewport = viewport.x > 0 && viewport.y > 0
            let contextChanged = previousContext != context
            let cameraChanged = previousViewProjection != viewProjection || previousViewport != viewport
            let needsRegeneration = hasValidViewport && (contextChanged || (contextHasCurves && cameraChanged))

            if needsRegeneration {
                let generator = GeometryGenerator(viewProjection: viewProjection, viewport: viewport)

                var allJoinData: [LineJoinGPUData] = []
                var allFillVertices: [Vertex] = []

                for command in context.commands {
                    switch command {
                    case let .stroke(path, color, style):
                        let joinData = generator.generateLineJoinGPUData(path: path, color: color, style: style)
                        allJoinData.append(contentsOf: joinData)
                    case let .fill(path, color):
                        let vertices = generator.generateFillGeometry(path: path, color: color)
                        allFillVertices.append(contentsOf: vertices)
                    case .text:
                        // Text is rendered by its own Slug pipeline, not as generated geometry.
                        break
                    }
                }

                joinDataBuffer = try Self.makeBuffer(device: device, contents: allJoinData, label: "GraphicsContext3D Join Data Buffer")
                joinCount = allJoinData.count

                fillVertexBuffer = try Self.makeBuffer(device: device, contents: allFillVertices, label: "GraphicsContext3D Fill Vertex Buffer")
                fillVertexCount = allFillVertices.count

                if contextChanged {
                    contextHasCurves = context.commands.contains { command in
                        switch command {
                        case let .stroke(path, _, _), let .fill(path, _):
                            GeometryGenerator.hasCurves(path)
                        case .text:
                            false
                        }
                    }
                }
                previousContext = context
                previousViewProjection = viewProjection
                previousViewport = viewport
            }

            // Uniforms are bound by value, so each frame gets its own copy.
            let uniforms = LineJoinUniforms(viewProjection: viewProjection, viewport: viewport, _padding: (0, 0))

            // Only build a pipeline when it has something to draw. An empty
            // mesh pipeline still binds mesh-stage buffers, which traps on GPUs
            // without mesh-shader support (issue #29).
            return try Group {
                if joinCount > 0, let joinDataBuffer {
                    try MeshRenderPipeline(label: "GraphicsContext3D Stroke", objectShader: objectShader, meshShader: meshShader, fragmentShader: meshFragmentShader) {
                        Draw { encoder in
                            encoder.setCullMode(.none)
                            encoder.setTriangleFillMode(debugWireframe ? .lines : .fill)
                            encoder.drawMeshThreadgroups(
                                threadgroupsPerGrid: MTLSize(width: joinCount, height: 1, depth: 1),
                                threadsPerObjectThreadgroup: MTLSize(width: 1, height: 1, depth: 1),
                                threadsPerMeshThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
                            )
                        }
                        .debugGroup("GraphicsContext3D Stroke Mesh Shader (joinCount: \(joinCount))")
                        .parameter("joinData", functionType: .mesh, buffer: joinDataBuffer, offset: 0)
                        .parameter("uniforms", functionType: .mesh, value: uniforms)
                    }
                    .depthCompare(function: .less, enabled: true)
                }

                if fillVertexCount > 0, let fillVertexBuffer {
                    try RenderPipeline(label: "GraphicsContext3D Fill", vertexShader: fillVertexShader, fragmentShader: fillFragmentShader) {
                        Draw { encoder in
                            encoder.setCullMode(.none)
                            encoder.setTriangleFillMode(debugWireframe ? .lines : .fill)
                            encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: fillVertexCount)
                        }
                        .debugGroup("GraphicsContext3D Fill Geometry (fillVertexCount: \(fillVertexCount))")
                        .parameter("vertices", functionType: .vertex, buffer: fillVertexBuffer, offset: 0)
                        .parameter("uniforms", functionType: .vertex, value: uniforms)
                    }
                    .depthCompare(function: .less, enabled: true)
                    .renderPipelineDescriptorTransformer { descriptor in
                        // Fill colors are non-premultiplied, so composite source-over.
                        guard let attachment = descriptor.colorAttachments[0] else {
                            return
                        }
                        attachment.blendingState = .enabled
                        attachment.rgbBlendOperation = .add
                        attachment.alphaBlendOperation = .add
                        attachment.sourceRGBBlendFactor = .sourceAlpha
                        attachment.sourceAlphaBlendFactor = .sourceAlpha
                        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                    }
                }

                #if arch(arm64)
                let textLabels = context.textLabels
                if !textLabels.isEmpty {
                    GraphicsContext3DTextPipeline(labels: textLabels, viewProjection: viewProjection, viewport: viewport)
                }
                #endif
            }
        }
    }

    private static func makeBuffer<T>(device: MTLDevice, contents: [T], label: String) throws -> MTLBuffer? {
        guard !contents.isEmpty else {
            return nil
        }
        let buffer = contents.withUnsafeBytes { bytes in
            device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
        }
        guard let buffer else {
            throw MetalSprocketsError.resourceCreationFailure("Failed to create \(label)")
        }
        buffer.label = label
        return buffer
    }
}
