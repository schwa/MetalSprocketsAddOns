import Accelerate
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Testing
@testable import MetalSprocketsAddOns
import MetalSprocketsSupport
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Golden Image Comparison

extension CGImage {
    /// Compare this image to a golden reference image
    func isEqualToGoldenImage(named name: String) throws -> Bool {
        do {
            let goldenImage = try goldenImage(named: name)
            guard try imageCompare(self, goldenImage) else {
                let url = URL(fileURLWithPath: "/tmp/\(name).png")
                try self.write(to: url)
                #if canImport(AppKit)
                url.revealInFinder()
                #endif
                throw MetalSprocketsError.validationError("Images are not equal. Actual image written to \(url.path)")
            }
            return true
        }
        catch {
            let url = URL(fileURLWithPath: "/tmp/\(name).png")
            try self.write(to: url)
            // Image written to /tmp for debugging
            return false
        }
    }
}

func goldenImage(named name: String) throws -> CGImage {
    let url = Bundle.module.resourceURL!
        .appendingPathComponent("Golden Images")
        .appendingPathComponent(name)
        .appendingPathExtension("png")
    let data = try Data(contentsOf: url)
    let imageSource = try CGImageSourceCreateWithData(data as CFData, nil)
        .orThrow(.resourceCreationFailure("Failed to create image source from data"))
    return try CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        .orThrow(.resourceCreationFailure("Failed to create image from source"))
}

/// Compare two images for equality using histogram analysis
/// - Parameters:
///   - image1: First image to compare
///   - image2: Second image to compare
///   - tolerance: Minimum percentage of pixels that must match (0.0 to 1.0). Default is 0.70 (70%)
///     which accommodates GPU interpolation differences in gradient/anti-aliased content
/// - Returns: true if images match within tolerance
func imageCompare(_ image1: CGImage, _ image2: CGImage, tolerance: Double = 0.70) throws -> Bool {
    // First check dimensions
    guard image1.width == image2.width && image1.height == image2.height else {
        print("Image dimensions don't match: \(image1.width)x\(image1.height) vs \(image2.width)x\(image2.height)")
        return false
    }

    let ciContext = CIContext()

    let ciImage1 = CIImage(cgImage: image1)
    let ciImage2 = CIImage(cgImage: image2)

    let difference = CIFilter.differenceBlendMode()
    difference.setValue(ciImage1, forKey: kCIInputImageKey)
    difference.setValue(ciImage2, forKey: kCIInputBackgroundImageKey)

    guard let differenceImage = difference.outputImage,
          let differenceCGImage = ciContext.createCGImage(differenceImage, from: differenceImage.extent) else {
        throw MetalSprocketsError.validationError("Failed to create difference image")
    }

    let histogram = try Histogram(image: differenceCGImage)
    // Check if RGB channels match within tolerance
    // Note: We don't check alpha as different image formats may have different alpha handling
    let redMatch = histogram.relativeRed[0]
    let greenMatch = histogram.relativeGreen[0]
    let blueMatch = histogram.relativeBlue[0]

    // Use tolerance to account for GPU rasterization/interpolation differences
    let result = redMatch >= tolerance && greenMatch >= tolerance && blueMatch >= tolerance

    if !result {
        print("Image comparison failed (tolerance: \(tolerance * 100)%):")
        print("  Red channel match: \(redMatch * 100)%")
        print("  Green channel match: \(greenMatch * 100)%")
        print("  Blue channel match: \(blueMatch * 100)%")
    }

    return result
}

// MARK: - Image Utilities

extension CGImage {
    func write(to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw MetalSprocketsError.resourceCreationFailure("Failed to create image destination")
        }
        CGImageDestinationAddImage(destination, self, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw MetalSprocketsError.resourceCreationFailure("Failed to finalize image destination")
        }
    }

    func toVimage() throws -> vImage.PixelBuffer<vImage.Interleaved8x4> {
        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
        var format = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 8 * 4,
            colorSpace: colorSpace,
            bitmapInfo: .init(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)
        )!
        return try vImage.PixelBuffer(cgImage: self, cgImageFormat: &format, pixelFormat: vImage.Interleaved8x4.self)
    }
}

// MARK: - Histogram Analysis

struct Histogram {
    var pixelCount: Int
    var red: [Int]
    var green: [Int]
    var blue: [Int]
    var alpha: [Int]

    init(image: CGImage) throws {
        let pixelBuffer = try image.toVimage()
        pixelCount = image.width * image.height
        let histogram = pixelBuffer.histogram()
        alpha = histogram.0.map { Int($0) }
        red = histogram.1.map { Int($0) }
        green = histogram.2.map { Int($0) }
        blue = histogram.3.map { Int($0) }
    }

    var peaks: (red: Double, green: Double, blue: Double, alpha: Double) {
        func peak(_ channel: [Int]) -> Double {
            let max = channel.max()!
            let index = channel.firstIndex(of: max)!
            return Double(index) / Double(channel.count - 1)
        }
        return (peak(red), peak(green), peak(blue), peak(alpha))
    }

    var relativeRed: [Double] {
        red.map { Double($0) / Double(pixelCount) }
    }

    var relativeGreen: [Double] {
        green.map { Double($0) / Double(pixelCount) }
    }

    var relativeBlue: [Double] {
        blue.map { Double($0) / Double(pixelCount) }
    }

    var relativeAlpha: [Double] {
        alpha.map { Double($0) / Double(pixelCount) }
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
