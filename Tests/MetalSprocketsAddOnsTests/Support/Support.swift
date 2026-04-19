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
