import CoreGraphics
import Foundation
import GoldenImage
import ImageIO
import Metal
import MetalSupport
import Testing
import UniformTypeIdentifiers

/// True when the current default device supports Metal 4. MetalSprockets renders only with Metal 4.
let supportsMetal4: Bool = MTLCreateSystemDefaultDevice()?.supportsMetal4 ?? false

extension Trait where Self == ConditionTrait {
    /// Skips a test that renders through MetalSprockets on a GPU without Metal 4.
    static var requiresMetal4: Self {
        .disabled(if: !supportsMetal4, "Needs a Metal 4 GPU")
    }
}

/// True when the current default device supports ray tracing.
let supportsRaytracing: Bool = MTLCreateSystemDefaultDevice()?.supportsRaytracing ?? false

/// True when the current default device has the 64-bit atomics the point cloud rasterizer needs.
let supportsPointCloud: Bool = MTLCreateSystemDefaultDevice()?.supportsFamily(.apple8) ?? false

/// Size of the demo scene renders.
let demoRenderSize = CGSize(width: 640, height: 400)

extension CGImage {
    /// Compares this image with a golden image in the test bundle. On a mismatch or a missing
    /// golden, writes the render to `/tmp/<name>.png`.
    func isEqualToGoldenImage(named name: String, psnrThreshold: Double = 30) throws -> Bool {
        let directory = try #require(Bundle.module.resourceURL).appendingPathComponent("Golden Images")
        let comparison = GoldenImageComparison(imageDirectory: directory, options: .none, psnrThreshold: psnrThreshold)
        let isMatch = (try? comparison.image(image: self, matchesGoldenImageNamed: name)) ?? false
        if !isMatch {
            let url = URL(fileURLWithPath: "/tmp/\(name).png")
            try write(to: url)
            print("Golden image mismatch for \"\(name)\". Render written to \(url.path)")
        }
        return isMatch
    }

    func write(to url: URL) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, self, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
