import Metal
import MetalSprockets
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import simd

// Point cloud rendering with compute shaders, after Schütz, Kerbl & Wimmer 2021,
// "Rendering Point Clouds with Compute Shaders and Vertex Order Optimization"
// (https://arxiv.org/abs/2104.07526).
//
// `PointCloudRasterizePass` runs as its own compute pass: each point does a 64-bit atomic min of
// (depth << 32 | colour) into a per-pixel buffer, so the nearest point per pixel wins.
// `PointCloudResolvePipeline` then runs inside the scene's render pass and writes that colour and
// depth, depth-tested against everything else in the pass.
//
// ```swift
// let framebuffer = PointCloudFramebuffer()
// Group {
//     try PointCloudRasterizePass(points: points, count: count, viewProjection: viewProjection, viewportSize: size, framebuffer: framebuffer)
//     try RenderPass {
//         // ... other scene geometry ...
//         try PointCloudResolvePipeline(framebuffer: framebuffer)
//     }
// }
// ```

public extension PointCloudPoint {
    init(position: SIMD3<Float>, color: SIMD4<UInt8>) {
        let packed = UInt32(color.x) | UInt32(color.y) << 8 | UInt32(color.z) << 16 | UInt32(color.w) << 24
        self.init(position: position, color: packed)
    }
}

/// The per-pixel buffer shared by ``PointCloudRasterizePass`` and ``PointCloudResolvePipeline``.
///
/// Create one per view and pass the same instance to both elements. The rasterize pass sizes it to
/// the viewport each frame.
public final class PointCloudFramebuffer {
    public private(set) var buffer: MTLBuffer?
    public private(set) var parameters: PointCloudParameters?

    public init() {
        // Buffer is created by the first rasterize pass.
    }

    /// Whether the device has the 64-bit buffer atomics the rasterizer needs.
    public static func isSupported(on device: MTLDevice) -> Bool {
        device.supportsFamily(.apple8)
    }

    fileprivate func prepare(device: MTLDevice, parameters: PointCloudParameters) throws -> MTLBuffer {
        let length = Int(parameters.viewportSize.x) * Int(parameters.viewportSize.y) * MemoryLayout<UInt64>.stride
        if let buffer, buffer.length == length, buffer.device === device {
            self.parameters = parameters
            return buffer
        }
        let buffer = try device.makeBuffer(length: length, options: .storageModePrivate)
            .orThrow(.resourceCreationFailure("Failed to create point cloud framebuffer"))
        buffer.label = "PointCloud Framebuffer"
        self.buffer = buffer
        self.parameters = parameters
        return buffer
    }
}

/// A consumer-supplied function that colours each point.
///
/// Write a Metal `[[visible]]` function with this signature, in any library (it can be compiled
/// from source at runtime):
///
/// ```metal
/// [[visible]] uint shadePoint(float3 position, uint color, uint pointIndex, const device void *userData) {
///     // `color` and the result are RGBA8 packed with red in the lowest byte.
///     return color;
/// }
/// ```
///
/// It runs once per point that lands in the viewport, and its result replaces the point's colour.
/// `userData` points at ``userData``; when that is `nil` it points at a small placeholder buffer
/// the function must not read.
public struct PointCloudShader {
    public var function: VisibleFunction
    public var userData: MTLBuffer?

    public init(_ function: VisibleFunction, userData: MTLBuffer? = nil) {
        self.function = function
        self.userData = userData
    }
}

/// Rasterizes points into a ``PointCloudFramebuffer`` with a compute pass.
///
/// - Important: This element runs its own compute pass, so place it as a sibling *before* the
///   render pass that contains the matching ``PointCloudResolvePipeline``.
public struct PointCloudRasterizePass: Element {
    let points: MTLBuffer
    let pointCount: Int
    let parameters: PointCloudParameters
    let framebuffer: PointCloudFramebuffer
    let shader: PointCloudShader?

    @MSState
    private var kernel = Self.kernel(hasShader: false)

    @MSState
    private var shadedKernel = Self.kernel(hasShader: true)

    // Bound as `userData` when the shader has none.
    @MSState
    private var emptyUserData: MTLBuffer?

    /// - Parameters:
    ///   - points: A buffer of `count` ``PointCloudPoint`` values.
    ///   - viewportSize: The size in pixels of the render target the resolve pass draws into.
    ///   - reverseZ: Set when the depth buffer uses reverse Z (nearer is larger, compare `.greater`).
    ///   - shader: Optional consumer function that computes each point's colour.
    public init(points: MTLBuffer, count: Int, viewProjection: float4x4, viewportSize: SIMD2<Int>, reverseZ: Bool = false, framebuffer: PointCloudFramebuffer, shader: PointCloudShader? = nil) throws {
        guard PointCloudFramebuffer.isSupported(on: points.device) else {
            throw MetalSprocketsError.configurationError("Point cloud rasterization needs 64-bit buffer atomics (Apple GPU family 8 or later).")
        }
        guard viewportSize.x > 0, viewportSize.y > 0 else {
            throw MetalSprocketsError.configurationError("Point cloud viewport size must be positive, got \(viewportSize).")
        }
        guard count * MemoryLayout<PointCloudPoint>.stride <= points.length else {
            throw MetalSprocketsError.configurationError("Point buffer holds fewer than \(count) points.")
        }
        self.points = points
        self.pointCount = count
        self.parameters = PointCloudParameters(
            viewProjection: viewProjection,
            viewportSize: SIMD2<UInt32>(UInt32(viewportSize.x), UInt32(viewportSize.y)),
            pointCount: UInt32(count),
            reverseZ: reverseZ ? 1 : 0
        )
        self.framebuffer = framebuffer
        self.shader = shader
    }

    private static func kernel(hasShader: Bool) -> ComputeKernel {
        var constants = FunctionConstants()
        constants["HAS_SHADER"] = .bool(hasShader)
        return ShaderLibrary.module.namespaced("PointCloud").requiredFunction(named: "rasterize", type: ComputeKernel.self, constants: constants)
    }

    public var body: some Element {
        get throws {
            let buffer = try framebuffer.prepare(device: points.device, parameters: parameters)
            let parameters = parameters
            let userData = try shader.map { shader in
                try shader.userData ?? emptyUserDataBuffer()
            }
            try ComputePass(label: "PointCloud Rasterize") {
                // Earlier frames' resolve passes may still read the buffer we are about to clear.
                QueueBarrier(after: [.fragment, .dispatch], before: [.blit, .dispatch])
                ComputeCommand { encoder in
                    encoder.fill(buffer: buffer, range: 0..<buffer.length, value: 0xFF)
                }
                .useComputeResources([buffer], usage: .write)
                EncoderBarrier(after: .blit, before: .dispatch)
                if pointCount > 0, let shader, let userData {
                    try ComputePipeline(label: "PointCloud Rasterize (Shaded)", computeKernel: shadedKernel) {
                        try dispatch(framebuffer: buffer, parameters: parameters)
                            .visibleFunctionTable("shaders", functions: [shader.function])
                            .parameter("userData", buffer: userData)
                    }
                    .linkedFunctions([shader.function])
                } else if pointCount > 0 {
                    try ComputePipeline(label: "PointCloud Rasterize", computeKernel: kernel) {
                        try dispatch(framebuffer: buffer, parameters: parameters)
                    }
                }
            }
            // The resolve pass reads the buffer from its fragment stage.
            .barrierAfterPass(after: .dispatch, beforeQueueStages: .fragment)
        }
    }

    private func dispatch(framebuffer: MTLBuffer, parameters: PointCloudParameters) throws -> some Element {
        try ComputeDispatch(
            threadsPerGrid: MTLSize(width: pointCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 128, height: 1, depth: 1)
        )
        .parameter("points", buffer: points)
        .parameter("framebuffer", buffer: framebuffer)
        .parameter("params", value: parameters)
    }

    private func emptyUserDataBuffer() throws -> MTLBuffer {
        if let emptyUserData {
            return emptyUserData
        }
        let buffer = try points.device.makeBuffer(length: 16, options: .storageModePrivate)
            .orThrow(.resourceCreationFailure("Failed to create point cloud user data buffer"))
        buffer.label = "PointCloud Empty User Data"
        emptyUserData = buffer
        return buffer
    }
}

/// Writes the rasterized points into the current render pass's colour and depth attachments.
///
/// Place it inside the render pass that follows ``PointCloudRasterizePass``. Points are
/// depth-tested against the rest of the pass, so the pass needs a depth attachment.
public struct PointCloudResolvePipeline: Element {
    let framebuffer: PointCloudFramebuffer

    @MSState
    private var vertexShader = ShaderLibrary.module.namespaced("PointCloud").requiredFunction(named: "resolve_vertex", type: VertexShader.self)

    @MSState
    private var fragmentShader = ShaderLibrary.module.namespaced("PointCloud").requiredFunction(named: "resolve_fragment", type: FragmentShader.self)

    public init(framebuffer: PointCloudFramebuffer) {
        self.framebuffer = framebuffer
    }

    public var body: some Element {
        get throws {
            let (buffer, parameters) = try rasterizedFrame()
            try RenderPipeline(label: "PointCloud Resolve", vertexShader: vertexShader, fragmentShader: fragmentShader) {
                Draw { encoder in
                    encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
                }
                .parameter("framebuffer", functionType: .fragment, buffer: buffer)
                .parameter("params", functionType: .fragment, value: parameters)
            }
            .depthCompare(function: parameters.reverseZ != 0 ? .greater : .less, enabled: true)
        }
    }

    private func rasterizedFrame() throws -> (MTLBuffer, PointCloudParameters) {
        guard let buffer = framebuffer.buffer, let parameters = framebuffer.parameters else {
            throw MetalSprocketsError.configurationError("PointCloudResolvePipeline needs a PointCloudRasterizePass earlier in the frame.")
        }
        return (buffer, parameters)
    }
}
