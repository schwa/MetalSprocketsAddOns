import CoreGraphics
import Foundation
import GoldenImage
import ImageIO
@testable import MetalSprocketsAddOns
import MetalSprocketsSupport
import Testing
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Golden Image Comparison

/// Default PSNR threshold for golden image comparisons.
/// Lower than the GoldenImage library default (120 dB) because GPU rasterization,
/// MSAA, and floating-point precision differences across hardware/drivers introduce
/// small per-pixel deviations even for "identical" renders.
private let defaultPSNRThreshold: Double = 30.0

extension CGImage {
    /// Compare this image to a golden reference image bundled in the test target.
    ///
    /// On mismatch (or missing golden), the rendered image is written to `/tmp/<name>.png`
    /// for inspection / promotion to a new golden.
    func isEqualToGoldenImage(named name: String, psnrThreshold: Double = defaultPSNRThreshold) throws -> Bool {
        let goldenImagesDir = Bundle.module.resourceURL!
            .appendingPathComponent("Golden Images")
        let comparison = GoldenImageComparison(
            imageDirectory: goldenImagesDir,
            options: .none,
            psnrThreshold: psnrThreshold
        )
        do {
            let isMatch = try comparison.image(image: self, matchesGoldenImageNamed: name)
            if !isMatch {
                let url = URL(fileURLWithPath: "/tmp/\(name).png")
                try self.write(to: url)
                print("Golden image mismatch for \"\(name)\". Rendered image written to: \(url.path)")
            }
            return isMatch
        } catch {
            // Includes the case where there is no golden image yet — the GoldenImage
            // library has already saved the rendered image to a temp location.
            let url = URL(fileURLWithPath: "/tmp/\(name).png")
            try? self.write(to: url)
            print("Golden image comparison threw for \"\(name)\": \(error). Rendered image written to: \(url.path)")
            return false
        }
    }
}

// MARK: - Image Utilities

extension CGImage {
    /// Fraction of pixels whose red, green and blue channels are all at or below `threshold`.
    ///
    /// Used by render tests to catch pipelines that run without error but produce no
    /// visible output (see issue #21).
    func fractionOfBlackPixels(threshold: UInt8 = 8) throws -> Double {
        let width = self.width
        let height = self.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
            throw MetalSprocketsError.resourceCreationFailure("Failed to create bitmap context")
        }
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        var blackCount = 0
        for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index] <= threshold && pixels[index + 1] <= threshold && pixels[index + 2] <= threshold {
            blackCount += 1
        }
        return Double(blackCount) / Double(width * height)
    }

    /// Luminance of a single pixel, in the range 0...1, with the origin at the top-left of the image.
    func luminance(atX x: Int, y: Int) throws -> Double {
        let width = self.width
        let height = self.height
        precondition((0..<width).contains(x) && (0..<height).contains(y), "Pixel (\(x), \(y)) is outside the \(width)x\(height) image")
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
            throw MetalSprocketsError.resourceCreationFailure("Failed to create bitmap context")
        }
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        let index = (y * width + x) * 4
        return (0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])) / 255.0
    }

    /// Mean luminance of the image, in the range 0...1.
    func meanLuminance() throws -> Double {
        let width = self.width
        let height = self.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
            throw MetalSprocketsError.resourceCreationFailure("Failed to create bitmap context")
        }
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        var total = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            total += 0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])
        }
        return total / Double(width * height) / 255.0
    }

    func write(to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw MetalSprocketsError.resourceCreationFailure("Failed to create image destination")
        }
        CGImageDestinationAddImage(destination, self, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw MetalSprocketsError.resourceCreationFailure("Failed to finalize image destination")
        }
    }
}

// MARK: - Finder Integration

#if canImport(AppKit)
public extension URL {
    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([self])
    }
}
#endif
