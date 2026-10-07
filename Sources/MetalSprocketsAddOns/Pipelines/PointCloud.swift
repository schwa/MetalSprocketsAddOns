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
    init(position: SIMD3<Float>, color: UInt32) {
        self.init(x: position.x, y: position.y, z: position.z, color: color)
    }

    init(position: SIMD3<Float>, color: SIMD4<UInt8>) {
        let packed = UInt32(color.x) | UInt32(color.y) << 8 | UInt32(color.z) << 16 | UInt32(color.w) << 24
        self.init(position: position, color: packed)
    }

    var position: SIMD3<Float> {
        get { SIMD3<Float>(x, y, z) }
        set { (x, y, z) = (newValue.x, newValue.y, newValue.z) }
    }
}

/// The per-pixel buffer shared by ``PointCloudRasterizePass`` and ``PointCloudResolvePipeline``.
///
/// Create one per view and pass the same instance to both elements. The rasterize pass sizes it to
/// the viewport each frame.
public final class PointCloudFramebuffer {
    /// The buffer for the frame being recorded.
    public private(set) var buffer: MTLBuffer?
    public private(set) var parameters: PointCloudParameters?

    // One buffer per frame in flight, so a frame never clears a buffer an earlier frame still reads.
    private var slots: [MTLBuffer?] = []

    public init() {
        // Buffer is created by the first rasterize pass.
    }

    /// Whether the device has the 64-bit buffer atomics the rasterizer needs.
    public static func isSupported(on device: MTLDevice) -> Bool {
        device.supportsFamily(.apple8)
    }

    /// Picks the buffer for this submission: `submissionIndex % slotCount`.
    fileprivate func prepare(device: MTLDevice, parameters: PointCloudParameters, submissionIndex: UInt64, slotCount: Int) throws -> MTLBuffer {
        let slotCount = max(slotCount, 1)
        if slots.count != slotCount {
            slots = Array(repeating: nil, count: slotCount)
        }
        let slot = Int(submissionIndex % UInt64(slotCount))
        let length = Int(parameters.viewportSize.x) * Int(parameters.viewportSize.y) * MemoryLayout<UInt64>.stride
        let buffer: MTLBuffer
        if let existing = slots[slot], existing.length == length, existing.device === device {
            buffer = existing
        } else {
            buffer = try device.makeBuffer(length: length, options: .storageModePrivate)
                .orThrow(.resourceCreationFailure("Failed to create point cloud framebuffer"))
            buffer.label = "PointCloud Framebuffer \(slot)"
            slots[slot] = buffer
        }
        self.buffer = buffer
        self.parameters = parameters
        return buffer
    }
}

/// A consumer-supplied function that describes each point: its position, colour, size and shape.
///
/// Write a Metal `[[visible]]` function with this signature, in any library. Include
/// `PointCloud.h` from MetalSprocketsAddOnsShaders, or, when compiling from source at runtime,
/// prepend `PointCloudShaderSupport.metalSource`:
///
/// ```metal
/// [[visible]] PointCloudSplat describePoint(uint index, const device void *points, const device void *userData) {
///     const device MyPoint &point = ((const device MyPoint *)points)[index];
///     return { point.position, point.color, 6.0, PointCloudShapeDisc };
/// }
/// ```
///
/// The points buffer can use any layout. Colours are RGBA8 with red in the lowest byte; sizes are
/// in pixels. `userData` points at the function's ``UserData``; with ``UserData/none`` it points at a
/// small placeholder the function must not read.
public struct PointCloudPointFunction {
    public enum UserData {
        case none
        /// A buffer you own. Writing it while earlier frames are in flight races with them.
        case buffer(MTLBuffer)
        /// Bytes copied into per-submission storage, so they can change every frame.
        case bytes([UInt8])
    }

    public var function: VisibleFunction
    public var userData: UserData

    public init(_ function: VisibleFunction, userData: MTLBuffer? = nil) {
        self.function = function
        self.userData = userData.map(UserData.buffer) ?? .none
    }

    /// Passes `userValue` (a plain-old-data value) to the function, copied per submission. Use this
    /// for values that change every frame, such as time or animation parameters.
    public init<Value>(_ function: VisibleFunction, userValue: Value) {
        assert(_isPOD(Value.self), "User value must be a POD type.")
        self.function = function
        self.userData = .bytes(withUnsafeBytes(of: userValue) { Array($0) })
    }
}

/// Metal declarations for runtime-compiled point-description functions.
public enum PointCloudShaderSupport {
    /// Matches `PointCloudSplat` and `PointCloudShape` in `PointCloud.h`.
    public static let metalSource = """
    #include <metal_stdlib>

    enum PointCloudShape : uint {
        PointCloudShapeSquare = 0,
        PointCloudShapeDisc = 1,
        PointCloudShapeCrosshair = 2,
        PointCloudShapeRing = 3,
    };

    struct PointCloudSplat {
        float3 position;
        uint color;
        float size;
        uint shape;
    };

    """
}

/// Rasterizes points into a ``PointCloudFramebuffer`` with a compute pass.
///
/// - Important: This element runs its own compute pass, so place it as a sibling *before* the
///   render pass that contains the matching ``PointCloudResolvePipeline``. It does not wait for
///   earlier GPU work, so if the points (or `userData`) are written on the GPU in the same frame,
///   order that work before this pass yourself.
public struct PointCloudRasterizePass: Element {
    let points: MTLBuffer
    let pointCount: Int
    let parameters: PointCloudParameters
    let framebuffer: PointCloudFramebuffer
    let describe: PointCloudPointFunction?

    @MSState
    private var kernel = Self.kernel(hasDescribe: false)

    @MSState
    private var describingKernel = Self.kernel(hasDescribe: true)

    // Bound as `userData` when the describe function has none.
    @MSState
    private var emptyUserData: MTLBuffer?

    @MSEnvironment(\.submissionIndex)
    private var submissionIndex

    @MSEnvironment(\.maximumInFlightSubmissions)
    private var maximumInFlightSubmissions

    /// - Parameters:
    ///   - points: A buffer of `count` points: ``PointCloudPoint`` values, or any layout `describe` reads.
    ///   - viewportSize: The size in pixels of the render target the resolve pass draws into.
    ///   - reverseZ: Set when the depth buffer uses reverse Z (nearer is larger, compare `.greater`).
    ///   - pointSize: Size in pixels for every point when `describe` is `nil`.
    ///   - shape: Shape for every point when `describe` is `nil`.
    ///   - maximumPointSize: Sizes above this, in pixels, are clamped.
    ///   - colorSpace: How the points' packed colours are encoded. Most 8-bit colour data is sRGB.
    ///   - describe: Optional consumer function that describes each point.
    public init(
        points: MTLBuffer,
        count: Int,
        viewProjection: float4x4,
        viewportSize: SIMD2<Int>,
        reverseZ: Bool = false,
        framebuffer: PointCloudFramebuffer,
        pointSize: Float = 1,
        shape: PointCloudShape = .square,
        maximumPointSize: Float = 64,
        colorSpace: PointCloudColorSpace = .sRGB,
        describe: PointCloudPointFunction? = nil
    ) throws {
        guard PointCloudFramebuffer.isSupported(on: points.device) else {
            throw MetalSprocketsError.configurationError("Point cloud rasterization needs 64-bit buffer atomics (Apple GPU family 8 or later).")
        }
        guard viewportSize.x > 0, viewportSize.y > 0 else {
            throw MetalSprocketsError.configurationError("Point cloud viewport size must be positive, got \(viewportSize).")
        }
        guard describe != nil || count * MemoryLayout<PointCloudPoint>.stride <= points.length else {
            throw MetalSprocketsError.configurationError("Point buffer holds fewer than \(count) points.")
        }
        self.points = points
        self.pointCount = count
        self.parameters = PointCloudParameters(
            viewProjection: viewProjection,
            viewportSize: SIMD2<UInt32>(UInt32(viewportSize.x), UInt32(viewportSize.y)),
            pointCount: UInt32(count),
            reverseZ: reverseZ ? 1 : 0,
            pointSize: pointSize,
            pointShape: shape.rawValue,
            maximumPointSize: maximumPointSize,
            colorSpace: colorSpace.rawValue
        )
        self.framebuffer = framebuffer
        self.describe = describe
    }

    private static func kernel(hasDescribe: Bool) -> ComputeKernel {
        var constants = FunctionConstants()
        constants["HAS_DESCRIBE"] = .bool(hasDescribe)
        return ShaderLibrary.module.namespaced("PointCloud").requiredFunction(named: "rasterize", type: ComputeKernel.self, constants: constants)
    }

    public var body: some Element {
        get throws {
            // Each submission gets its own buffer, so no earlier frame can still be reading this one.
            let buffer = try framebuffer.prepare(device: points.device, parameters: parameters, submissionIndex: submissionIndex, slotCount: maximumInFlightSubmissions)
            let parameters = parameters
            let placeholder = try describe.map { _ in try emptyUserDataBuffer() }
            try ComputePass(label: "PointCloud Rasterize") {
                ComputeCommand { encoder in
                    encoder.fill(buffer: buffer, range: 0..<buffer.length, value: 0xFF)
                }
                .useComputeResources([buffer], usage: .write)
                EncoderBarrier(after: .blit, before: .dispatch)
                if pointCount > 0, let describe, let placeholder {
                    try ComputePipeline(label: "PointCloud Rasterize (Described)", computeKernel: describingKernel) {
                        try dispatch(framebuffer: buffer, parameters: parameters)
                            .visibleFunctionTable("describe", functions: [describe.function])
                            .parameters { parameters in
                                switch describe.userData {
                                case .none:
                                    parameters.set("userData", buffer: placeholder)
                                case .buffer(let userData):
                                    parameters.set("userData", buffer: userData)
                                case .bytes(let bytes):
                                    // Values are copied into storage owned by this submission.
                                    parameters.set("userData", values: bytes.isEmpty ? [0] : bytes)
                                }
                            }
                    }
                    .linkedFunctions([describe.function])
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
