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
struct PointCloudDemoView: View {
    @State private var camera = OrbitCamera(pitch: -.pi / 8, distance: 6, target: [0, 0.5, 0])
    @State private var scene: PointCloudDemoScene?
    @State private var pointCount = PointCloudDemoScene.pointCounts[2]
    @State private var colorMode = PointCloudDemoScene.ColorMode.position
    @State private var showGrid = true

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
                PointCloudRenderView(scene: scene, camera: camera, showGrid: showGrid)
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

    var body: some View {
        RenderView { _, drawableSize in
            try scene.element(camera: camera, drawableSize: drawableSize, showGrid: showGrid)
        }
        .metalDepthStencilPixelFormat(.depth32Float)
        .metalClearColor(PointCloudDemoScene.clearColor)
    }
}

/// The generated points and per-frame scene, separate from the view so tests can render it offscreen.
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

    init(pointCount: Int, colorMode: ColorMode) throws {
        let device = _MTLCreateSystemDefaultDevice()
        let buffer = try device.makeBuffer(length: pointCount * MemoryLayout<PointCloudPoint>.stride, options: .storageModeShared)
            .orThrow(.resourceCreationFailure("Failed to create point buffer"))
        buffer.label = "PointCloud Demo Points"
        let points = buffer.contents().bindMemory(to: PointCloudPoint.self, capacity: pointCount)
        var generator = SplitMix64(seed: 0x5EED)
        for index in 0..<pointCount {
            points[index] = Self.point(index: index, of: pointCount, colorMode: colorMode, generator: &generator)
        }
        self.points = buffer
        self.pointCount = pointCount
    }

    /// A point on a thick (2, 3) torus knot, jittered inside the tube.
    private static func point(index: Int, of count: Int, colorMode: ColorMode, generator: inout SplitMix64) -> PointCloudPoint {
        let t = Float(index) / Float(count) * 2 * .pi
        let radius = 1.2 + 0.5 * cos(3 * t)
        let centre = SIMD3<Float>(radius * cos(2 * t), 0.5 * sin(3 * t) + 1, radius * sin(2 * t))
        let offset = SIMD3<Float>(generator.nextSigned(), generator.nextSigned(), generator.nextSigned())
        let position = centre + offset * 0.18

        let color: SIMD3<Float>
        switch colorMode {
        case .position:
            color = simd_clamp((position + SIMD3<Float>(1.7, 0, 1.7)) / SIMD3<Float>(3.4, 2, 3.4), .zero, .one)
        case .height:
            let height = simd_clamp(position.y / 2, 0, 1)
            color = simd_mix(SIMD3<Float>(0.1, 0.3, 1), SIMD3<Float>(1, 0.8, 0.2), SIMD3<Float>(repeating: height))
        case .random:
            color = SIMD3<Float>(generator.nextUnit(), generator.nextUnit(), generator.nextUnit())
        }
        let bytes = SIMD3<UInt8>(color * 255)
        return PointCloudPoint(position: position, color: SIMD4<UInt8>(bytes, 255))
    }

    func element(camera: OrbitCamera, drawableSize: CGSize, showGrid: Bool) throws -> some Element {
        let projection = camera.projectionMatrix(drawableSize: drawableSize)
        let viewportSize = SIMD2<Int>(Int(drawableSize.width), Int(drawableSize.height))
        return try MetalSprockets.Group {
            try PointCloudRasterizePass(
                points: points,
                count: pointCount,
                viewProjection: projection * camera.viewMatrix,
                viewportSize: viewportSize,
                framebuffer: framebuffer
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

/// Small deterministic generator so the demo (and its golden image) is reproducible.
private struct SplitMix64 {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    /// Uniform in [0, 1).
    mutating func nextUnit() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }

    /// Uniform in [-1, 1).
    mutating func nextSigned() -> Float {
        nextUnit() * 2 - 1
    }
}

#Preview {
    PointCloudDemoView()
}
