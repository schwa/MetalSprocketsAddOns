import CoreGraphics
import Foundation
import Metal
import MetalSupport
import SwiftUI

/// A SwiftUI view that displays a Metal texture as a SwiftUI `Image`.
///
/// `TextureView` converts an `MTLTexture` into a `CGImage` and presents it
/// using a SwiftUI `Image`. Because its `body` returns `Image`, all standard
/// image modifiers work — `.resizable()`, `.interpolation(_:)`,
/// `.antialiased(_:)`, `.renderingMode(_:)`, etc.
///
/// ```swift
/// TextureView(texture)
///     .resizable()
///     .interpolation(.high)
///     .scaledToFit()
/// ```
///
/// The `CGImage` is cached and only recomputed when the texture's identity
/// changes (`ObjectIdentifier`). For animated / per-frame textures, prefer
/// `RenderView`.
public struct TextureView: View {
    private let texture: MTLTexture?
    private let scale: CGFloat
    private let label: Text?

    @State private var cache = ImageCache()

    /// Creates a decorative texture view.
    ///
    /// - Parameters:
    ///   - texture: The texture to display. If `nil` or conversion fails,
    ///     a 1×1 transparent image is shown.
    ///   - scale: The scale factor for the image. Defaults to `1`.
    public init(_ texture: MTLTexture?, scale: CGFloat = 1) {
        self.texture = texture
        self.scale = scale
        self.label = nil
    }

    /// Creates a labeled texture view.
    ///
    /// - Parameters:
    ///   - texture: The texture to display.
    ///   - scale: The scale factor for the image. Defaults to `1`.
    ///   - label: The accessibility label for the image.
    public init(_ texture: MTLTexture?, scale: CGFloat = 1, label: Text) {
        self.texture = texture
        self.scale = scale
        self.label = label
    }

    public var body: Image {
        let cgImage = cache.image(for: texture) ?? Self.placeholder
        if let label {
            return Image(cgImage, scale: scale, label: label)
        }
        return Image(decorative: cgImage, scale: scale)
    }

    // swiftlint:disable force_unwrapping multiline_arguments
    private static let placeholder: CGImage = {
        let cs = CGColorSpaceCreateDeviceRGB()
        let bytes: [UInt8] = [0, 0, 0, 0]
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
            space: cs,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }()
    // swiftlint:enable force_unwrapping multiline_arguments
}

/// Reference-typed cache so `body` can update it without triggering
/// "Modifying state during view update" warnings.
internal final class ImageCache {
    // Weak, not an ObjectIdentifier: a new texture can be allocated at a freed texture's address,
    // and an identifier would then match the stale image (#77).
    private(set) weak var cachedTexture: MTLTexture?
    private var cachedImage: CGImage?

    func image(for texture: MTLTexture?) -> CGImage? {
        guard let texture else {
            cachedTexture = nil
            cachedImage = nil
            return nil
        }
        if let cachedTexture, cachedTexture === texture, let cachedImage {
            return cachedImage
        }
        guard let image = try? texture.toCGImage() else {
            return nil
        }
        cachedTexture = texture
        cachedImage = image
        return image
    }
}
