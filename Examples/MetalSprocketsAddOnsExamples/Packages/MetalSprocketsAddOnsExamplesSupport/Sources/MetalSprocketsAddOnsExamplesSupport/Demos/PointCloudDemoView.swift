import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsUI
import MetalSupport
import simd
import SwiftUI

/// Compute-shader point cloud rendering (Schütz, Kerbl & Wimmer 2021).
///
/// `PointCloudRasterizePass` does a 64-bit atomic min of packed depth and colour per pixel in a
/// compute pass, then `PointCloudResolvePipeline` writes the winners into the render pass, where
/// they depth-test against the grid like any other geometry.
///
/// "Custom Shader" swaps in a consumer-supplied `[[visible]]` function, compiled from source at
/// runtime, that recolours each point.
struct PointCloudDemoView: View {
    @State private var camera = OrbitCamera(pitch: -.pi / 8, distance: 6, target: [0, 0.5, 0])
    @State private var scene: PointCloudDemoScene?
    @State private var pointCount = PointCloudDemoScene.pointCounts[2]
    @State private var colorMode = PointCloudDemoScene.ColorMode.position
    @State private var showGrid = true
    @State private var useCustomShader = false

    private var isSupported: Bool {
        PointCloudFramebuffer.isSupported(on: _MTLCreateSystemDefaultDevice())
    }

    var body: some View {
        DemoLayoutView {
            if !isSupported {
                ContentUnavailableView(
                    "64-bit Atomics Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Point cloud rasterization needs Apple GPU family 8 or later.")
                )
            } else if let scene {
                PointCloudRenderView(scene: scene, camera: camera, showGrid: showGrid, useCustomShader: useCustomShader)
                    .orbitCamera($camera)
            } else {
                ProgressView("Generating Points")
            }
        } controls: {
            Picker("Points", selection: $pointCount) {
                ForEach(PointCloudDemoScene.pointCounts, id: \.self) { count in
                    Text(count.formatted()).tag(count)
                }
            }
            Picker("Colour", selection: $colorMode) {
                ForEach(PointCloudDemoScene.ColorMode.allCases, id: \.self) { mode in
                    Text(mode.name).tag(mode)
                }
            }
            Toggle("Custom Shader", isOn: $useCustomShader)
            Toggle("Grid", isOn: $showGrid)
        }
        .task(id: PointCloudDemoScene.Key(pointCount: pointCount, colorMode: colorMode)) {
            guard isSupported else {
                return
            }
            let pointCount = pointCount
            let colorMode = colorMode
            scene = try? await Task.detached(priority: .userInitiated) {
                try PointCloudDemoScene(pointCount: pointCount, colorMode: colorMode)
            }.value
        }
    }
}

private struct PointCloudRenderView: View {
    let scene: PointCloudDemoScene
    let camera: OrbitCamera
    let showGrid: Bool
    let useCustomShader: Bool

    var body: some View {
        RenderView { _, drawableSize in
            try scene.element(camera: camera, drawableSize: drawableSize, showGrid: showGrid, useCustomShader: useCustomShader)
        }
        .metalDepthStencilPixelFormat(.depth32Float)
        .metalClearColor(PointCloudDemoScene.clearColor)
    }
}

/// The generated points and per-frame scene, separate from the view so tests can render it offscreen.
///
/// Points are generated on the GPU by a kernel compiled from source at runtime.
///
/// `@unchecked Sendable`: built off the main actor, then only read; the framebuffer is only
/// touched while the element tree is walked.
final class PointCloudDemoScene: @unchecked Sendable {
    enum ColorMode: String, CaseIterable, Hashable, Sendable {
        case position
        case height
        case random

        var name: String {
            switch self {
            case .position: "Position"
            case .height: "Height"
            case .random: "Random"
            }
        }

        /// Matches the `colorMode` switch in `generatorSource`.
        var shaderValue: UInt32 {
            switch self {
            case .position: 0
            case .height: 1
            case .random: 2
            }
        }
    }

    struct Key: Equatable {
        var pointCount: Int
        var colorMode: ColorMode
    }

    static let pointCounts = [100_000, 1_000_000, 4_000_000, 8_000_000]
    static let clearColor = MTLClearColor(red: 0.03, green: 0.03, blue: 0.05, alpha: 1)

    let points: MTLBuffer
    let pointCount: Int
    let framebuffer = PointCloudFramebuffer()
    let customShader: PointCloudShader

    /// A consumer shader: height bands, spaced by the float in `userData`, tinting the point's colour.
    static let customShaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    [[visible]] uint heightBands(float3 position, uint color, uint pointIndex, const device void *userData) {
        float spacing = ((const device float *)userData)[0];
        float band = fract(position.y / spacing);
        float4 rgba = unpack_unorm4x8_to_float(color);
        float3 tint = band < 0.5 ? float3(1.0, 0.45, 0.1) : float3(0.1, 0.6, 1.0);
        return pack_float_to_unorm4x8(float4(mix(rgba.rgb, tint, 0.7), rgba.a));
    }
    """

    /// Points on a thick (2, 3) torus knot, jittered inside the tube. Jitter and random colours
    /// come from a hash of the point index, so the output is the same on every run.
    static let generatorSource = """
    #include <metal_stdlib>
    using namespace metal;

    // Same layout as PointCloudPoint in PointCloud.h.
    struct Point {
        float3 position;
        uint color;
    };

    // PCG hash (Jarzynski & Olano 2020).
    uint hash(uint value) {
        uint state = value * 747796405u + 2891336453u;
        uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
        return (word >> 22u) ^ word;
    }

    // Uniform in [0, 1) from the index and a per-use salt.
    float unit(uint index, uint salt) {
        return float(hash(index * 6u + salt) >> 8) / 16777216.0;
    }

    kernel void generatePoints(
        uint index [[thread_position_in_grid]],
        device Point *points [[buffer(0)]],
        constant uint &count [[buffer(1)]],
        constant uint &colorMode [[buffer(2)]]
    ) {
        if (index >= count) {
            return;
        }
        float t = float(index) / float(count) * 2.0 * M_PI_F;
        float radius = 1.2 + 0.5 * cos(3.0 * t);
        float3 centre = float3(radius * cos(2.0 * t), 0.5 * sin(3.0 * t) + 1.0, radius * sin(2.0 * t));
        float3 offset = float3(unit(index, 0), unit(index, 1), unit(index, 2)) * 2.0 - 1.0;
        float3 position = centre + offset * 0.18;

        float3 color;
        switch (colorMode) {
        case 0:
            color = saturate((position + float3(1.7, 0.0, 1.7)) / float3(3.4, 2.0, 3.4));
            break;
        case 1:
            color = mix(float3(0.1, 0.3, 1.0), float3(1.0, 0.8, 0.2), saturate(position.y / 2.0));
            break;
        default:
            color = float3(unit(index, 3), unit(index, 4), unit(index, 5));
            break;
        }
        points[index] = { position, pack_float_to_unorm4x8(float4(color, 1.0)) };
    }
    """

    init(pointCount: Int, colorMode: ColorMode) throws {
        let device = _MTLCreateSystemDefaultDevice()
        let buffer = try device.makeBuffer(length: pointCount * MemoryLayout<PointCloudPoint>.stride, options: .storageModePrivate)
            .orThrow(.resourceCreationFailure("Failed to create point buffer"))
        buffer.label = "PointCloud Demo Points"
        let kernel = try ShaderLibrary(source: Self.generatorSource).function(type: ComputeKernel.self, named: "generatePoints")
        try ComputePass(label: "PointCloud Demo Generate") {
            try ComputePipeline(label: "PointCloud Demo Generate", computeKernel: kernel) {
                try ComputeDispatch(
                    threadsPerGrid: MTLSize(width: pointCount, height: 1, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1)
                )
                .parameter("points", buffer: buffer)
                .parameter("count", value: UInt32(pointCount))
                .parameter("colorMode", value: colorMode.shaderValue)
            }
        }
        .run()
        self.points = buffer
        self.pointCount = pointCount

        let library = try ShaderLibrary(source: Self.customShaderSource)
        let spacing = try device.makeBuffer(unsafeBytesOf: [Float(0.15)])
        customShader = PointCloudShader(try library.function(type: VisibleFunction.self, named: "heightBands"), userData: spacing)
    }

    func element(camera: OrbitCamera, drawableSize: CGSize, showGrid: Bool, useCustomShader: Bool = false) throws -> some Element {
        let projection = camera.projectionMatrix(drawableSize: drawableSize)
        let viewportSize = SIMD2<Int>(Int(drawableSize.width), Int(drawableSize.height))
        return try MetalSprockets.Group {
            try PointCloudRasterizePass(
                points: points,
                count: pointCount,
                viewProjection: projection * camera.viewMatrix,
                viewportSize: viewportSize,
                framebuffer: framebuffer,
                shader: useCustomShader ? customShader : nil
            )
            try RenderPass {
                if showGrid {
                    GridShader(projectionMatrix: projection, cameraMatrix: camera.cameraMatrix)
                }
                try PointCloudResolvePipeline(framebuffer: framebuffer)
            }
        }
    }
}

#Preview {
    PointCloudDemoView()
}
