import CoreGraphics
import CoreText
import Metal
import simd

/// Manages glyph curve data and band textures for a single font.
internal final class SlugFontAtlas {
    // MARK: - Nested Types

    struct GlyphInfo {
        var advanceWidth: Float
        var xMin: Float, yMin: Float, xMax: Float, yMax: Float
        var curveTexStart: Int, curveCount: Int
        var bandTexX: Int, bandTexY: Int
        var numHorizBands: Int, numVertBands: Int
        var bandScaleX: Float, bandScaleY: Float, bandOffsetX: Float, bandOffsetY: Float

        var isEmpty: Bool { curveCount == 0 }

        static let empty = Self(
            advanceWidth: 0,
            xMin: 0, yMin: 0, xMax: 0, yMax: 0,
            curveTexStart: 0, curveCount: 0,
            bandTexX: 0, bandTexY: 0,
            numHorizBands: 0, numVertBands: 0,
            bandScaleX: 0, bandScaleY: 0, bandOffsetX: 0, bandOffsetY: 0
        )
    }

    struct QuadBezier {
        var p0: SIMD2<Float>, p1: SIMD2<Float>, p2: SIMD2<Float>

        var minX: Float { min(p0.x, min(p1.x, p2.x)) }
        var maxX: Float { max(p0.x, max(p1.x, p2.x)) }
        var minY: Float { min(p0.y, min(p1.y, p2.y)) }
        var maxY: Float { max(p0.y, max(p1.y, p2.y)) }

        var isStraightHorizontal: Bool {
            abs(p0.y - p2.y) < 1e-5 && abs(p1.y - (p0.y + p2.y) * 0.5) < 1e-5
        }
        var isStraightVertical: Bool {
            abs(p0.x - p2.x) < 1e-5 && abs(p1.x - (p0.x + p2.x) * 0.5) < 1e-5
        }
    }

    enum TextureConstants {
        static let curveTextureWidth = 4_096
        static let bandTextureWidth = 4_096
    }

    // MARK: - Properties

    private let device: MTLDevice
    private let font: CTFont

    /// Cache of glyph info, keyed by glyph ID.
    private var glyphCache: [CGGlyph: GlyphInfo] = [:]

    /// Curve texture data (RGBA16F, 4 half-floats per texel).
    private var curvePixels: [Float16] = []
    /// Band texture data (RG16Uint, 2 uint16s per texel).
    private var bandPixels: [UInt16] = []

    /// Next free texel index in curve texture.
    private var curveTexCursor = 0
    /// Next free texel index in band texture.
    private var bandTexCursor = 0

    /// The curve texture (RGBA16Float).
    private(set) var curveTexture: MTLTexture?
    /// The band texture (RG16Uint).
    private(set) var bandTexture: MTLTexture?

    /// Creates a font atlas for the given font name.
    /// - Parameters:
    ///   - fontName: PostScript name of the font (e.g., "HelveticaNeue").
    ///   - device: Metal device for texture creation.
    init(fontName: String, device: MTLDevice) {
        self.device = device
        // Create font at size 1.0 (em units)
        self.font = CTFontCreateWithName(fontName as CFString, 1.0, nil)
    }

    /// Ensures the given glyphs are in the atlas, uploading textures if needed.
    func insertGlyphs(_ glyphs: [CGGlyph]) {
        var didUpdate = false
        for glyph in glyphs {
            if glyphCache[glyph] == nil {
                ensureGlyph(glyph)
                didUpdate = true
            }
        }
        if didUpdate {
            uploadTextures()
        }
    }

    /// Returns cached info for a glyph, or empty info if not found.
    func glyphInfo(for glyph: CGGlyph) -> GlyphInfo {
        glyphCache[glyph] ?? .empty
    }

    // MARK: - Private

    private func ensureGlyph(_ glyph: CGGlyph) {
        var glyphForAdvance = glyph
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyphForAdvance, &advance, 1)
        let advanceEm = Float(advance.width)

        guard let path = CTFontCreatePathForGlyph(font, glyph, nil) else {
            // Trivial glyph without a path (e.g., whitespace)
            glyphCache[glyph] = GlyphInfo(
                advanceWidth: advanceEm,
                xMin: 0, yMin: 0, xMax: advanceEm, yMax: 0,
                curveTexStart: 0, curveCount: 0,
                bandTexX: 0, bandTexY: 0,
                numHorizBands: 0, numVertBands: 0,
                bandScaleX: 0, bandScaleY: 0,
                bandOffsetX: 0, bandOffsetY: 0
            )
            return
        }

        let curves = extractQuadBeziers(from: path)

        if curves.isEmpty {
            glyphCache[glyph] = GlyphInfo(
                advanceWidth: advanceEm,
                xMin: 0, yMin: 0, xMax: advanceEm, yMax: 0,
                curveTexStart: 0, curveCount: 0,
                bandTexX: 0, bandTexY: 0,
                numHorizBands: 0, numVertBands: 0,
                bandScaleX: 0, bandScaleY: 0,
                bandOffsetX: 0, bandOffsetY: 0
            )
            return
        }

        // Compute glyph bounds
        let xMin = curves.map(\.minX).min() ?? 0
        let xMax = curves.map(\.maxX).max() ?? 0
        let yMin = curves.map(\.minY).min() ?? 0
        let yMax = curves.map(\.maxY).max() ?? 0

        let curveStart = curveTexCursor

        // Write curve data and collect texture coordinates
        var curveTexCoords: [SIMD2<Int>] = []
        for curve in curves {
            let idx = curveTexCursor
            let tx = idx % TextureConstants.curveTextureWidth
            let ty = idx / TextureConstants.curveTextureWidth
            curveTexCoords.append(SIMD2(tx, ty))

            // Texel 0: (p0.x, p0.y, p1.x, p1.y)
            writeCurveTexel(curve.p0.x, curve.p0.y, curve.p1.x, curve.p1.y)
            // Texel 1: (p2.x, p2.y, 0, 0)
            writeCurveTexel(curve.p2.x, curve.p2.y, 0, 0)
        }

        // Build horizontal and vertical bands
        let numH = 8
        let numV = 8
        let eps: Float = 1.0 / 1_024.0

        let hBandHeight = (yMax - yMin) / Float(numH)
        let vBandWidth = (xMax - xMin) / Float(numV)

        // Horizontal bands (cast along +X)
        var hBands: [[Int]] = []
        for b in 0 ..< numH {
            let bYMin = yMin + Float(b) * hBandHeight - eps
            let bYMax = yMin + Float(b + 1) * hBandHeight + eps
            var indices: [Int] = []
            for (i, curve) in curves.enumerated() {
                if curve.isStraightHorizontal { continue }
                if curve.maxY >= bYMin, curve.minY <= bYMax {
                    indices.append(i)
                }
            }
            // Sort descending by max X (early-out optimization)
            indices.sort { curves[$0].maxX > curves[$1].maxX }
            hBands.append(indices)
        }

        // Vertical bands (cast along +Y)
        var vBands: [[Int]] = []
        for b in 0 ..< numV {
            let bXMin = xMin + Float(b) * vBandWidth - eps
            let bXMax = xMin + Float(b + 1) * vBandWidth + eps
            var indices: [Int] = []
            for (i, curve) in curves.enumerated() {
                if curve.isStraightVertical { continue }
                if curve.maxX >= bXMin, curve.minX <= bXMax {
                    indices.append(i)
                }
            }
            // Sort descending by max Y
            indices.sort { curves[$0].maxY > curves[$1].maxY }
            vBands.append(indices)
        }

        let bandStartLinear = bandTexCursor
        let bandStartX = bandStartLinear % TextureConstants.bandTextureWidth
        let bandStartY = bandStartLinear / TextureConstants.bandTextureWidth

        // Reserve header slots (numH + numV headers)
        let headerCount = numH + numV
        let headerOffset = bandTexCursor

        // Pre-fill header slots with zeros (will be filled in later)
        for _ in 0 ..< headerCount {
            writeBandTexel(0, 0)
        }

        // Write horizontal band curve lists
        var hCurveListOffsets: [Int] = []
        for b in 0 ..< numH {
            let relOffset = bandTexCursor - bandStartLinear
            hCurveListOffsets.append(relOffset)
            for ci in hBands[b] {
                let t = curveTexCoords[ci]
                writeBandTexel(UInt16(t.x), UInt16(t.y))
            }
        }

        // Write vertical band curve lists
        var vCurveListOffsets: [Int] = []
        for b in 0 ..< numV {
            let relOffset = bandTexCursor - bandStartLinear
            vCurveListOffsets.append(relOffset)
            for ci in vBands[b] {
                let t = curveTexCoords[ci]
                writeBandTexel(UInt16(t.x), UInt16(t.y))
            }
        }

        // Write headers (count, relativeOffset)
        var ptr = headerOffset
        for b in 0 ..< numH {
            let count = hBands[b].count
            let offset = hCurveListOffsets[b]
            // Ensure we have space in bandPixels
            let pixelIndex = ptr * 2
            while bandPixels.count <= pixelIndex + 1 {
                bandPixels.append(0)
            }
            bandPixels[pixelIndex] = UInt16(count)
            bandPixels[pixelIndex + 1] = UInt16(offset)
            ptr += 1
        }
        for b in 0 ..< numV {
            let count = vBands[b].count
            let offset = vCurveListOffsets[b]
            let pixelIndex = ptr * 2
            while bandPixels.count <= pixelIndex + 1 {
                bandPixels.append(0)
            }
            bandPixels[pixelIndex] = UInt16(count)
            bandPixels[pixelIndex + 1] = UInt16(offset)
            ptr += 1
        }

        // Band transform: maps em-space -> band index
        let bSX = Float(numV) / max(xMax - xMin, 1e-6)
        let bSY = Float(numH) / max(yMax - yMin, 1e-6)
        let bOX = -xMin * bSX
        let bOY = -yMin * bSY

        glyphCache[glyph] = GlyphInfo(
            advanceWidth: advanceEm,
            xMin: xMin, yMin: yMin, xMax: xMax, yMax: yMax,
            curveTexStart: curveStart, curveCount: curves.count,
            bandTexX: bandStartX, bandTexY: bandStartY,
            numHorizBands: numH, numVertBands: numV,
            bandScaleX: bSX, bandScaleY: bSY,
            bandOffsetX: bOX, bandOffsetY: bOY
        )
    }

    private func writeCurveTexel(_ r: Float, _ g: Float, _ b: Float, _ a: Float) {
        curvePixels.append(Float16(r))
        curvePixels.append(Float16(g))
        curvePixels.append(Float16(b))
        curvePixels.append(Float16(a))
        curveTexCursor += 1
    }

    private func writeBandTexel(_ r: UInt16, _ g: UInt16) {
        bandPixels.append(r)
        bandPixels.append(g)
        bandTexCursor += 1
    }

    private func uploadTextures() {
        let cw = TextureConstants.curveTextureWidth
        let ch = max(1, (curveTexCursor + cw - 1) / cw)
        let bw = TextureConstants.bandTextureWidth
        let bh = max(1, (bandTexCursor + bw - 1) / bw)

        // Curve texture (RGBA16Float)
        let curveDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: cw,
            height: ch,
            mipmapped: false
        )
        curveDesc.usage = .shaderRead
        curveDesc.storageMode = .shared

        if let ct = device.makeTexture(descriptor: curveDesc) {
            ct.label = "Slug Curve Texture (\(CTFontCopyPostScriptName(font)))"
            // Pad a COPY to fill the texture (don't mutate source array)
            var paddedCurve = curvePixels
            let requiredCurvePixels = cw * ch * 4
            while paddedCurve.count < requiredCurvePixels {
                paddedCurve.append(0)
            }
            ct.replace(
                region: MTLRegionMake2D(0, 0, cw, ch),
                mipmapLevel: 0,
                withBytes: paddedCurve,
                bytesPerRow: MemoryLayout<Float16>.stride * cw * 4
            )
            curveTexture = ct
        }

        // Band texture (RG16Uint)
        let bandDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg16Uint,
            width: bw,
            height: bh,
            mipmapped: false
        )
        bandDesc.usage = .shaderRead
        bandDesc.storageMode = .shared

        if let bt = device.makeTexture(descriptor: bandDesc) {
            bt.label = "Slug Band Texture (\(CTFontCopyPostScriptName(font)))"
            // Pad a COPY to fill the texture (don't mutate source array)
            var paddedBand = bandPixels
            let requiredBandPixels = bw * bh * 2
            while paddedBand.count < requiredBandPixels {
                paddedBand.append(0)
            }
            bt.replace(
                region: MTLRegionMake2D(0, 0, bw, bh),
                mipmapLevel: 0,
                withBytes: paddedBand,
                bytesPerRow: MemoryLayout<UInt16>.stride * bw * 2
            )
            bandTexture = bt
        }
    }

    // MARK: - Bezier Extraction

    private func extractQuadBeziers(from path: CGPath) -> [QuadBezier] {
        var result: [QuadBezier] = []
        var subpathStart = CGPoint.zero
        var current = CGPoint.zero

        path.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint:
                let p = element.pointee.points[0]
                subpathStart = p
                current = p

            case .addLineToPoint:
                let p1 = element.pointee.points[0]
                let mid = CGPoint(x: (current.x + p1.x) * 0.5, y: (current.y + p1.y) * 0.5)
                result.append(QuadBezier(
                    p0: SIMD2(Float(current.x), Float(current.y)),
                    p1: SIMD2(Float(mid.x), Float(mid.y)),
                    p2: SIMD2(Float(p1.x), Float(p1.y))
                ))
                current = p1

            case .addQuadCurveToPoint:
                let ctrl = element.pointee.points[0]
                let end = element.pointee.points[1]
                result.append(QuadBezier(
                    p0: SIMD2(Float(current.x), Float(current.y)),
                    p1: SIMD2(Float(ctrl.x), Float(ctrl.y)),
                    p2: SIMD2(Float(end.x), Float(end.y))
                ))
                current = end

            case .addCurveToPoint:
                // Cubic to quadratic conversion via subdivision at t=0.5
                let c1 = element.pointee.points[0]
                let c2 = element.pointee.points[1]
                let ep = element.pointee.points[2]
                let quads = cubicToQuadratic(p0: current, c1: c1, c2: c2, p3: ep)
                result.append(contentsOf: quads)
                current = ep

            case .closeSubpath:
                let distSq = pow(current.x - subpathStart.x, 2) + pow(current.y - subpathStart.y, 2)
                if distSq > 1e-10 {
                    let mid = CGPoint(
                        x: (current.x + subpathStart.x) * 0.5,
                        y: (current.y + subpathStart.y) * 0.5
                    )
                    result.append(QuadBezier(
                        p0: SIMD2(Float(current.x), Float(current.y)),
                        p1: SIMD2(Float(mid.x), Float(mid.y)),
                        p2: SIMD2(Float(subpathStart.x), Float(subpathStart.y))
                    ))
                }
                current = subpathStart

            @unknown default:
                break
            }
        }

        return result
    }

    private func cubicToQuadratic(p0: CGPoint, c1: CGPoint, c2: CGPoint, p3: CGPoint) -> [QuadBezier] {
        func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }

        let m01 = lerp(p0, c1, 0.5)
        let m12 = lerp(c1, c2, 0.5)
        let m23 = lerp(c2, p3, 0.5)
        let m012 = lerp(m01, m12, 0.5)
        let m123 = lerp(m12, m23, 0.5)
        let mid = lerp(m012, m123, 0.5)

        return [
            QuadBezier(
                p0: SIMD2(Float(p0.x), Float(p0.y)),
                p1: SIMD2(Float(m012.x), Float(m012.y)),
                p2: SIMD2(Float(mid.x), Float(mid.y))
            ),
            QuadBezier(
                p0: SIMD2(Float(mid.x), Float(mid.y)),
                p1: SIMD2(Float(m123.x), Float(m123.y)),
                p2: SIMD2(Float(p3.x), Float(p3.y))
            )
        ]
    }
}
