import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSupport
import os
import simd
import Testing

private func randomPoints(count: Int, seed: UInt64 = 1) -> [PointCloudPoint] {
    var generator = TestRandom(state: seed)
    return (0..<count).map { index in
        let position = SIMD3<Float>(
            Float.random(in: -1...1, using: &generator),
            Float.random(in: -1...1, using: &generator),
            Float.random(in: -1...1, using: &generator)
        )
        // Index in the colour so tests can check the result is a permutation.
        return PointCloudPoint(position: position, color: UInt32(index))
    }
}

@Test
func testMortonCode_interleavesAxes() {
    #expect(PointCloudOrder.mortonCode([1, 0, 0]) == 0b001)
    #expect(PointCloudOrder.mortonCode([0, 1, 0]) == 0b010)
    #expect(PointCloudOrder.mortonCode([0, 0, 1]) == 0b100)
    #expect(PointCloudOrder.mortonCode([3, 0, 0]) == 0b001_001)
    let maximum = UInt32((1 << 21) - 1)
    #expect(PointCloudOrder.mortonCode([maximum, maximum, maximum]) == UInt64.max >> 1)
}

@Test
func testMortonOrder_isPermutationAndGroupsNeighbours() {
    let original = randomPoints(count: 10_000)
    var points = original
    PointCloudOrder.morton.apply(to: &points)
    #expect(Set(points.map(\.color)) == Set(original.map(\.color)))

    // Consecutive points should be far closer together than in random order.
    func meanStep(_ points: [PointCloudPoint]) -> Float {
        zip(points, points.dropFirst()).map { distance($0.position, $1.position) }.reduce(0, +) / Float(points.count - 1)
    }
    #expect(meanStep(points) < meanStep(original) / 10)
}

@Test
func testShuffledMortonOrder_keepsBatchesIntact() {
    var morton = randomPoints(count: 10_000)
    PointCloudOrder.morton.apply(to: &morton)
    var shuffled = randomPoints(count: 10_000)
    PointCloudOrder.shuffledMorton.apply(to: &shuffled, batchSize: 100, seed: 7)

    #expect(shuffled.map(\.color) != morton.map(\.color))
    let mortonBatches = Set(stride(from: 0, to: morton.count, by: 100).map { morton[$0..<$0 + 100].map(\.color) })
    let shuffledBatches = Set(stride(from: 0, to: shuffled.count, by: 100).map { shuffled[$0..<$0 + 100].map(\.color) })
    #expect(mortonBatches == shuffledBatches)
}

// MARK: - Benchmark

/// GPU time of the rasterize pass for each point order. Opt in with POINT_CLOUD_BENCHMARK=1;
/// results are printed and written to /tmp/PointCloudBenchmark.txt rather than asserted,
/// because they vary by GPU.
@Test(.requiresMetal4, .enabled(if: ProcessInfo.processInfo.environment["POINT_CLOUD_BENCHMARK"] != nil))
@MainActor
func benchmarkPointCloudOrders() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let count = 8_000_000
    let viewProjection = perspectiveProjection() * float4x4(translation: SIMD3<Float>(0, 0, 3)).inverse
    let size = SIMD2<Int>(1_920, 1_080)
    let renderer = try OffscreenRenderer(size: CGSize(width: size.x, height: size.y))
    // A filled volume, and a surface like the scanned data in the paper. Both start in random order.
    let volume = randomPoints(count: count)
    let surface = volume.map { point in
        PointCloudPoint(position: normalize(point.position), color: point.color)
    }

    let orders: [PointCloudOrder?] = [nil] + PointCloudOrder.allCases.map(Optional.some)
    let cases = [("volume", volume), ("surface", surface)].flatMap { dataset in orders.map { (dataset, $0) } }

    var results: [(String, Double, Double)] = []
    for ((dataset, source), order) in cases {
        var points = source
        order?.apply(to: &points)
        let buffer = try device.makeBuffer(unsafeBytesOf: points)
        let framebuffer = PointCloudFramebuffer()
        let samples = OSAllocatedUnfairLock<[TimeInterval]>(initialState: [])
        for _ in 0..<80 {
            let element = try MetalSprockets.Group {
                try PointCloudRasterizePass(points: buffer, count: count, viewProjection: viewProjection, viewportSize: size, framebuffer: framebuffer)
                    .gpuCounters { sample in
                        if let duration = sample.duration {
                            samples.withLock { $0.append(duration) }
                        }
                    }
                try RenderPass {
                    try PointCloudResolvePipeline(framebuffer: framebuffer)
                }
            }
            _ = try renderer.render(element)
        }
        // Drop warm-up frames.
        let durations = samples.withLock { $0 }.dropFirst(20).sorted()
        let median = durations.isEmpty ? .nan : durations[durations.count / 2]
        let minimum = durations.first ?? .nan
        results.append(("\(dataset) \(order?.rawValue ?? "random")", median * 1_000, minimum * 1_000))
    }
    let lines = results.map { name, median, minimum in
        "PointCloud benchmark \(count) points, \(name): median \(String(format: "%.2f", median)) ms, min \(String(format: "%.2f", minimum)) ms"
    }
    let report = lines.joined(separator: "\n")
    print(report)
    try report.write(toFile: "/tmp/PointCloudBenchmark.txt", atomically: true, encoding: .utf8)
}

/// GPU time of the rasterize pass as the point count grows (random cube, random order). Opt in with
/// POINT_CLOUD_BENCHMARK=1; results are written to /tmp/PointCloudScaling.txt.
@Test(.requiresMetal4, .enabled(if: ProcessInfo.processInfo.environment["POINT_CLOUD_BENCHMARK"] != nil))
@MainActor
func benchmarkPointCloudScaling() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let viewProjection = perspectiveProjection() * float4x4(translation: SIMD3<Float>(0, 0, 3)).inverse
    let size = SIMD2<Int>(1_920, 1_080)
    let renderer = try OffscreenRenderer(size: CGSize(width: size.x, height: size.y))

    var lines: [String] = []
    for count in [8_000_000, 32_000_000, 100_000_000, 250_000_000] {
        let buffer = try device.makeBuffer(length: count * MemoryLayout<PointCloudPoint>.stride, options: .storageModeShared)
            .orThrow(.resourceCreationFailure("Failed to create \(count) point buffer"))
        let points = buffer.contents().bindMemory(to: PointCloudPoint.self, capacity: count)
        var generator = TestRandom(state: 1)
        for index in 0..<count {
            let position = SIMD3<Float>(
                Float.random(in: -1...1, using: &generator),
                Float.random(in: -1...1, using: &generator),
                Float.random(in: -1...1, using: &generator)
            )
            points[index] = PointCloudPoint(position: position, color: UInt32(truncatingIfNeeded: index))
        }
        let framebuffer = PointCloudFramebuffer()
        let samples = OSAllocatedUnfairLock<[TimeInterval]>(initialState: [])
        for _ in 0..<40 {
            let element = try MetalSprockets.Group {
                try PointCloudRasterizePass(points: buffer, count: count, viewProjection: viewProjection, viewportSize: size, framebuffer: framebuffer)
                    .gpuCounters { sample in
                        if let duration = sample.duration {
                            samples.withLock { $0.append(duration) }
                        }
                    }
                try RenderPass {
                    try PointCloudResolvePipeline(framebuffer: framebuffer)
                }
            }
            _ = try renderer.render(element)
        }
        let durations = samples.withLock { $0 }.dropFirst(10).sorted()
        let median = durations.isEmpty ? .nan : durations[durations.count / 2] * 1_000
        let minimum = (durations.first ?? .nan) * 1_000
        lines.append("PointCloud scaling \(count) points: median \(String(format: "%.2f", median)) ms, min \(String(format: "%.2f", minimum)) ms")
    }
    let report = lines.joined(separator: "\n")
    print(report)
    try report.write(toFile: "/tmp/PointCloudScaling.txt", atomically: true, encoding: .utf8)
}

private struct TestRandom: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
