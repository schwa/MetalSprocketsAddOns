import MetalSprocketsAddOnsShaders
import simd

/// Point orders for ``PointCloudRasterizePass``, from Schütz, Kerbl & Wimmer 2021 (section 5).
///
/// Order changes how fast the rasterizer runs, not what it draws. Neighbouring GPU threads that
/// project to nearby pixels share cache lines; but threads that hit the *same* pixel at the same
/// time contend on its atomic. Morton order gives coherence; shuffled Morton keeps coherence
/// within small batches while spreading the batches apart to cut contention.
public enum PointCloudOrder: String, CaseIterable, Sendable {
    /// Sorted along a Z-order (Morton) curve over the points' bounding box.
    case morton
    /// Morton order, then batches of consecutive points shuffled.
    case shuffledMorton
}

public extension PointCloudOrder {
    /// Points per batch for ``shuffledMorton``.
    static let defaultBatchSize = 128

    /// Reorders `points` in place.
    ///
    /// - Parameters:
    ///   - batchSize: Batch size for ``shuffledMorton``.
    ///   - seed: Seed for the batch shuffle, so results are reproducible.
    func apply(to points: inout [PointCloudPoint], batchSize: Int = defaultBatchSize, seed: UInt64 = 0) {
        switch self {
        case .morton:
            Self.sortByMorton(&points)
        case .shuffledMorton:
            Self.sortByMorton(&points)
            Self.shuffleBatches(&points, batchSize: batchSize, seed: seed)
        }
    }

    internal static func sortByMorton(_ points: inout [PointCloudPoint]) {
        guard let first = points.first else {
            return
        }
        var lower = first.position
        var upper = first.position
        for point in points {
            lower = simd_min(lower, point.position)
            upper = simd_max(upper, point.position)
        }
        // Quantize each axis to 21 bits so the 3D code fits a UInt64.
        let scale = SIMD3<Float>(repeating: Float((1 << 21) - 1)) / simd_max(upper - lower, SIMD3<Float>(repeating: .leastNormalMagnitude))
        var keyed = points.map { point in
            let cell = SIMD3<UInt32>(simd_clamp((point.position - lower) * scale, .zero, SIMD3<Float>(repeating: Float((1 << 21) - 1))))
            return (code: mortonCode(cell), point: point)
        }
        keyed.sort { $0.code < $1.code }
        points = keyed.map(\.point)
    }

    internal static func shuffleBatches(_ points: inout [PointCloudPoint], batchSize: Int, seed: UInt64) {
        precondition(batchSize > 0, "Batch size must be positive")
        var batches = stride(from: 0, to: points.count, by: batchSize).map { start in
            points[start..<min(start + batchSize, points.count)]
        }
        var generator = SplitMix64(state: seed)
        batches.shuffle(using: &generator)
        points = Array(batches.joined())
    }

    /// Interleaves the low 21 bits of each axis: x in bit 0, y in bit 1, z in bit 2.
    internal static func mortonCode(_ cell: SIMD3<UInt32>) -> UInt64 {
        spread(cell.x) | spread(cell.y) << 1 | spread(cell.z) << 2
    }

    /// Spreads the low 21 bits of `value` so there are two zero bits between each.
    private static func spread(_ value: UInt32) -> UInt64 {
        var bits = UInt64(value & 0x1F_FFFF)
        bits = (bits | bits << 32) & 0x1F_0000_0000_FFFF
        bits = (bits | bits << 16) & 0x1F_0000_FF00_00FF
        bits = (bits | bits << 8) & 0x100F_00F0_0F00_F00F
        bits = (bits | bits << 4) & 0x10C3_0C30_C30C_30C3
        bits = (bits | bits << 2) & 0x1249_2492_4924_9249
        return bits
    }
}

/// Small deterministic generator for reproducible shuffles.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
