// FastBlurPipeline Unit Tests
//
//   just test-one FastBlur

import Metal
import MetalSprockets
@testable import MetalSprocketsAddOns
import MetalSprocketsSupport
import MetalSupport
import Testing

@Test
func testFastBlurPlan_keepsVarianceAcrossFactors() {
    for step in 0...400 {
        let sigma = Float(step) * 0.25
        let plan = FastBlurPipeline.plan(sigma: sigma, size: 4_096)
        #expect(plan.workingSigma >= 0)
        if plan.factor > 1 {
            #expect(plan.workingSigma >= FastBlurPipeline.minimumWorkingSigma)
            let factor = Float(plan.factor)
            let total = plan.workingSigma * plan.workingSigma * factor * factor
                + (factor * factor - 1) / 12
                + FastBlurPipeline.upsampleVariance(factor: plan.factor, bSpline: plan.bSpline)
            #expect(abs(total - sigma * sigma) < 0.01 * sigma * sigma)
        }
    }
    #expect(FastBlurPipeline.plan(sigma: 100, size: 4_096).factor > 10)
}

@Test(.requiresMetal4)
@MainActor
func testFastBlurPipeline_impulseHasRequestedSigma() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let size = 512
    var previous: Float = 0
    for sigma: Float in stride(from: 1, through: 40, by: 0.5) {
        let (measured, total) = try measureImpulse(device: device, size: size, sigma: SIMD2(sigma, sigma))
        #expect(abs(total.x - 1) < 0.02, "sigma \(sigma): energy \(total)")
        #expect(abs(measured.x - sigma) < 0.03 * sigma + 0.05, "sigma \(sigma): measured \(measured.x)")
        #expect(abs(measured.y - sigma) < 0.03 * sigma + 0.05, "sigma \(sigma): measured \(measured.y)")
        // Smoothly increasing as sigma grows, including across downsample factor changes.
        #expect(measured.x > previous, "sigma \(sigma): measured \(measured.x) not above \(previous)")
        previous = measured.x
    }
}

@Test(.requiresMetal4)
@MainActor
func testFastBlurPipeline_separateAxes() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let (measured, _) = try measureImpulse(device: device, size: 256, sigma: [20, 3])
    #expect(abs(measured.x - 20) < 2)
    #expect(abs(measured.y - 3) < 0.5)
}

// MARK: - Helpers

/// Blurs a single bright pixel and returns the standard deviation of the result per axis and its total energy.
@MainActor
private func measureImpulse(device: MTLDevice, size: Int, sigma: SIMD2<Float>) throws -> (SIMD2<Float>, SIMD2<Float>) {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: size, height: size, mipmapped: false)
    descriptor.usage = [.shaderRead, .shaderWrite]
    descriptor.storageMode = .shared
    let source = try device.makeTexture(descriptor: descriptor).orThrow(.resourceCreationFailure("source"))
    let destination = try device.makeTexture(descriptor: descriptor).orThrow(.resourceCreationFailure("destination"))

    let center = size / 2 + 3
    var pixels = [Float](repeating: 0, count: size * size * 4)
    pixels[(center * size + center) * 4] = 1
    source.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0, withBytes: pixels, bytesPerRow: size * 16)

    try FastBlurPipeline(source: source, destination: destination, sigma: sigma).run()

    destination.getBytes(&pixels, bytesPerRow: size * 16, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
    var total: Float = 0
    var mean = SIMD2<Float>.zero
    for y in 0..<size {
        for x in 0..<size {
            let value = pixels[(y * size + x) * 4]
            total += value
            mean += value * SIMD2(Float(x), Float(y))
        }
    }
    mean /= total
    var variance = SIMD2<Float>.zero
    for y in 0..<size {
        for x in 0..<size {
            let value = pixels[(y * size + x) * 4]
            let delta = SIMD2(Float(x), Float(y)) - mean
            variance += value * delta * delta
        }
    }
    variance /= total
    return (SIMD2(variance.x.squareRoot(), variance.y.squareRoot()), SIMD2(repeating: total))
}
