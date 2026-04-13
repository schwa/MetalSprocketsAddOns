import CoreGraphics
import CoreText
import Metal
import simd
import SwiftUI

#if canImport(AppKit)
import AppKit
private typealias PlatformFont = NSFont
#elseif canImport(UIKit)
import UIKit
private typealias PlatformFont = UIFont
#endif

/// Builds text meshes from attributed strings using the Slug algorithm.
/// All meshes share a single vertex and index buffer for efficiency.
///
/// Usage:
/// ```swift
/// let builder = SlugTextMeshBuilder(device: device)
/// let mesh1 = builder.buildMesh(attributedString: str1, ...)
/// let mesh2 = builder.buildMesh(attributedString: str2, ...)
/// let meshes = builder.finalize() // Returns all meshes with shared buffers
/// ```
/// Opaque container for sharing font atlas data between SlugTextMeshBuilder instances.
/// Avoids re-rasterizing glyphs when rebuilding scenes with the same fonts.
public struct FontAtlasCache: @unchecked Sendable {
    internal var cache: [String: SlugFontAtlas]
    internal var orderedFontNames: [String]
}

public let defaultMaximumSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

public final class SlugTextMeshBuilder {
    private struct PendingMesh {
        let vertexBufferOffset: Int
        let indexBufferOffset: Int
        let indexCount: Int
        let bounds: CGRect
    }

    private let device: MTLDevice

    /// Cache of font atlases, keyed by PostScript font name.
    private var fontAtlasCache: [String: SlugFontAtlas]

    /// Ordered font index mapping for argument buffer construction.
    private var fontIndexMap: [String: UInt16] = [:]
    private var orderedFontNames: [String] = []

    /// Accumulated vertex data for all meshes.
    private var allVertices: [GlyphVertex] = []
    /// Accumulated index data for all meshes.
    private var allIndices: [UInt32] = []

    /// Pending meshes awaiting finalization.
    private var pendingMeshes: [PendingMesh] = []

    /// Whether finalize() has been called.
    private var isFinalized = false

    public init(device: MTLDevice) {
        self.device = device
        self.fontAtlasCache = [:]
    }

    /// Creates a builder that shares font atlas cache with a previous builder.
    /// This avoids re-rasterizing glyphs when rebuilding scenes with the same fonts.
    public init(device: MTLDevice, fontAtlasCache: FontAtlasCache) {
        self.device = device
        self.fontAtlasCache = fontAtlasCache.cache
        // Restore font index mapping from the cache
        for (index, name) in fontAtlasCache.orderedFontNames.enumerated() {
            fontIndexMap[name] = UInt16(index)
        }
        self.orderedFontNames = fontAtlasCache.orderedFontNames
    }

    /// Returns the font atlas cache for sharing with future builders.
    public var sharedFontAtlasCache: FontAtlasCache {
        FontAtlasCache(cache: fontAtlasCache, orderedFontNames: orderedFontNames)
    }

    /// Queues a text mesh to be built. Call `finalize()` after adding all meshes.
    /// Returns a stable index for this mesh. Empty strings produce a mesh with 0 indices.
    @discardableResult
    public func buildMesh(
        attributedString: NSAttributedString,
        maximumSize: CGSize = defaultMaximumSize
    ) -> Int {
        precondition(!isFinalized, "Cannot add meshes after finalize() has been called")

        // Track where this mesh starts in the shared buffers
        let vertexStart = allVertices.count
        let indexStart = allIndices.count

        var vertices: [GlyphVertex] = []
        var indices: [UInt32] = []

        // Create CoreText frame
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            maximumSize,
            nil
        )
        let framePath = CGPath(rect: CGRect(origin: .zero, size: suggestedSize), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), framePath, nil)
        let lines = CTFrameGetLines(frame) as! [CTLine]

        guard !lines.isEmpty else { return appendEmptyMesh() }

        // Get line origins
        var lineOrigins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &lineOrigins)

        // Normalize so first line's baseline is at Y=0
        let firstLineY = lineOrigins[0].y

        // FIRST PASS: Collect all glyphs per font and insert them all at once
        var glyphsByFont: [String: [CGGlyph]] = [:]
        for line in lines {
            let runs = CTLineGetGlyphRuns(line) as! [CTRun]
            for run in runs {
                let attrs = CTRunGetAttributes(run) as! [CFString: Any]
                let font = attrs[kCTFontAttributeName] as! CTFont
                let fontName = CTFontCopyPostScriptName(font) as String

                let glyphCount = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)

                glyphsByFont[fontName, default: []].append(contentsOf: glyphs)
            }
        }

        // Insert all glyphs into each atlas (single upload per font)
        for (fontName, glyphs) in glyphsByFont {
            let atlas = fontAtlas(for: fontName)
            atlas.insertGlyphs(glyphs)
        }

        var boundsMinX: Float = .greatestFiniteMagnitude
        var boundsMinY: Float = .greatestFiniteMagnitude
        var boundsMaxX: Float = -.greatestFiniteMagnitude
        var boundsMaxY: Float = -.greatestFiniteMagnitude

        // SECOND PASS: Build vertices and submeshes
        for (lineIdx, line) in lines.enumerated() {
            let lineOrigin = lineOrigins[lineIdx]
            let runs = CTLineGetGlyphRuns(line) as! [CTRun]

            for run in runs {
                let attrs = CTRunGetAttributes(run) as! [CFString: Any]
                let font = attrs[kCTFontAttributeName] as! CTFont
                let fontSize = CTFontGetSize(font)

                // Get PostScript font name
                let fontName = CTFontCopyPostScriptName(font) as String

                // Get font atlas (already populated)
                let atlas = fontAtlas(for: fontName)

                // Get glyphs and positions
                let glyphCount = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)

                var positions = [CGPoint](repeating: .zero, count: glyphCount)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)

                // Extract foreground color (convert to linear sRGB)
                var runColor = SIMD4<Float>(1, 1, 1, 1)
                var fgColor: CGColor?

                let colorValue = attrs[kCTForegroundColorAttributeName]
                    ?? attrs["NSColor" as CFString]

                if let color = colorValue {
                    if CFGetTypeID(color as CFTypeRef) == CGColor.typeID {
                        fgColor = (color as! CGColor)
                    } else {
                        #if canImport(AppKit)
                        if let nsColor = color as? NSColor {
                            fgColor = nsColor.cgColor
                        }
                        #elseif canImport(UIKit)
                        if let uiColor = color as? UIColor {
                            fgColor = uiColor.cgColor
                        }
                        #endif
                    }
                }

                if let fgColor,
                   let linearSRGB = CGColorSpace(name: CGColorSpace.linearSRGB),
                   let linearColor = fgColor.converted(to: linearSRGB, intent: .defaultIntent, options: nil),
                   let components = linearColor.components {
                    let n = linearColor.numberOfComponents
                    if n >= 4 {
                        runColor = SIMD4(Float(components[0]), Float(components[1]), Float(components[2]), Float(components[3]))
                    } else if n >= 2 {
                        runColor = SIMD4(Float(components[0]), Float(components[0]), Float(components[0]), Float(components[1]))
                    }
                }

                for (glyphIdx, glyph) in glyphs.enumerated() {
                    let info = atlas.glyphInfo(for: glyph)

                    if info.isEmpty { continue }

                    let posX = Float(lineOrigin.x + positions[glyphIdx].x)
                    let posY = Float(lineOrigin.y - firstLineY + positions[glyphIdx].y)

                    let margin: Float = 0.02
                    let ex0 = info.xMin - margin
                    let ex1 = info.xMax + margin
                    let ey0 = info.yMin - margin
                    let ey1 = info.yMax + margin

                    let fontScale = Float(fontSize)
                    let px0 = ex0 * fontScale
                    let py0 = ey0 * fontScale
                    let px1 = ex1 * fontScale
                    let py1 = ey1 * fontScale

                    boundsMinX = min(boundsMinX, posX + px0)
                    boundsMinY = min(boundsMinY, posY + py0)
                    boundsMaxX = max(boundsMaxX, posX + px1)
                    boundsMaxY = max(boundsMaxY, posY + py1)

                    let glocX = UInt32(info.bandTexX)
                    let glocY = UInt32(info.bandTexY)
                    let texZPacked = glocX | (glocY << 16)
                    let texZ = Float(bitPattern: texZPacked)

                    let bmaxX = UInt32(info.numVertBands - 1)
                    let bmaxY = UInt32(info.numHorizBands - 1)
                    let texWPacked = bmaxX | (bmaxY << 16)
                    let texW = Float(bitPattern: texWPacked)

                    let band = SIMD4<Float>(info.bandScaleX, info.bandScaleY, info.bandOffsetX, info.bandOffsetY)

                    let invScale = 1.0 / fontScale
                    let invJacobian = SIMD4<Float>(invScale, 0, 0, invScale)

                    let corners: [(px: Float, py: Float, ex: Float, ey: Float)] = [
                        (px0, py0, ex0, ey0),
                        (px1, py0, ex1, ey0),
                        (px1, py1, ex1, ey1),
                        (px0, py1, ex0, ey1)
                    ]

                    let baseIndex = UInt32(vertices.count)

                    for corner in corners {
                        let norm = simd_normalize(SIMD2<Float>(corner.ex, corner.ey))
                        let vertex = GlyphVertex(
                            posAndNorm: SIMD4(posX + corner.px, posY + corner.py, norm.x, norm.y),
                            texAndAtlasOffsets: SIMD4(corner.ex, corner.ey, texZ, texW),
                            invJacobian: invJacobian,
                            bandTransform: band,
                            color: runColor,
                            indices: SIMD2<UInt32>(
                                UInt32(fontIndexMap[fontName] ?? 0),
                                UInt32(pendingMeshes.count)
                            )
                        )
                        vertices.append(vertex)
                    }

                    indices.append(baseIndex)
                    indices.append(baseIndex + 1)
                    indices.append(baseIndex + 2)
                    indices.append(baseIndex)
                    indices.append(baseIndex + 2)
                    indices.append(baseIndex + 3)
                }
            }
        }

        guard !vertices.isEmpty else { return appendEmptyMesh() }

        // Append to shared arrays, offsetting indices to be global
        let globalVertexOffset = UInt32(allVertices.count)
        allVertices.append(contentsOf: vertices)
        allIndices.append(contentsOf: indices.map { $0 + globalVertexOffset })

        // Compute bounds
        var bounds = CGRect.zero
        if boundsMaxX > boundsMinX, boundsMaxY > boundsMinY {
            bounds = CGRect(
                x: CGFloat(boundsMinX),
                y: CGFloat(boundsMinY),
                width: CGFloat(boundsMaxX - boundsMinX),
                height: CGFloat(boundsMaxY - boundsMinY)
            )
        }

        let index = pendingMeshes.count
        pendingMeshes.append(PendingMesh(
            vertexBufferOffset: vertexStart * MemoryLayout<GlyphVertex>.stride,
            indexBufferOffset: indexStart * MemoryLayout<UInt32>.stride,
            indexCount: indices.count,
            bounds: bounds
        ))

        return index
    }

    private func appendEmptyMesh() -> Int {
        let index = pendingMeshes.count
        pendingMeshes.append(PendingMesh(
            vertexBufferOffset: allVertices.count * MemoryLayout<GlyphVertex>.stride,
            indexBufferOffset: allIndices.count * MemoryLayout<UInt32>.stride,
            indexCount: 0,
            bounds: .zero
        ))
        return index
    }

    /// Finalizes all pending meshes and returns a SlugScene containing all GPU resources.
    public func finalize() throws -> SlugScene {
        precondition(!isFinalized, "finalize() can only be called once")
        isFinalized = true

        guard !allVertices.isEmpty else { throw SlugError.noMeshes }

        guard let vertexBuffer = device.makeBuffer(
            bytes: allVertices,
            length: MemoryLayout<GlyphVertex>.stride * allVertices.count,
            options: .storageModeShared
        ) else { throw SlugError.bufferCreationFailed("vertex") }
        vertexBuffer.label = "Slug Shared Vertex Buffer"

        guard let indexBuffer = device.makeBuffer(
            bytes: allIndices,
            length: MemoryLayout<UInt32>.stride * allIndices.count,
            options: .storageModeShared
        ) else { throw SlugError.bufferCreationFailed("index") }
        indexBuffer.label = "Slug Shared Index Buffer"

        let storage = SlugBufferStorage(vertexBuffer: vertexBuffer, indexBuffer: indexBuffer, totalIndexCount: allIndices.count)

        let meshes = pendingMeshes.map { pending in
            SlugTextMesh(
                bufferStorage: storage,
                vertexBufferOffset: pending.vertexBufferOffset,
                indexBufferOffset: pending.indexBufferOffset,
                indexCount: pending.indexCount,
                bounds: pending.bounds
            )
        }

        // Pre-allocate model matrices buffer (one identity matrix per mesh)
        let matrixCount = meshes.count
        guard let modelMatricesBuffer = device.makeBuffer(
            length: matrixCount * MemoryLayout<float4x4>.stride,
            options: .storageModeShared
        ) else { throw SlugError.bufferCreationFailed("model matrices") }
        modelMatricesBuffer.label = "Slug Model Matrices"

        // Initialize to identity
        let ptr = modelMatricesBuffer.contents().bindMemory(to: float4x4.self, capacity: matrixCount)
        for i in 0..<matrixCount {
            ptr[i] = float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))
        }

        return SlugScene(
            bufferStorage: storage,
            meshes: meshes,
            fontTexturePairs: fontTexturePairs,
            modelMatricesBuffer: modelMatricesBuffer
        )
    }

    // MARK: - Glyph Prepopulation

    /// Pre-populates all glyphs from the given attributed strings into font atlases.
    /// Call this before buildMesh() to ensure all textures are stable.
    public func prepopulateGlyphs(from strings: [AttributedString]) {
        prepopulateGlyphs(from: strings.map { NSAttributedString($0) })
    }

    /// Pre-populates all glyphs from the given attributed strings into font atlases.
    /// Call this before buildMesh() to ensure all textures are stable.
    public func prepopulateGlyphs(from strings: [NSAttributedString]) {
        for attributedString in strings {
            let fullRange = NSRange(location: 0, length: attributedString.length)

            attributedString.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
                guard let font = attrs[.font] as? PlatformFont else { return }

                let substring = attributedString.attributedSubstring(from: range).string
                let ctFont = font as CTFont
                let fontName = CTFontCopyPostScriptName(ctFont) as String

                var unichars = Array(substring.utf16)
                var glyphs = [CGGlyph](repeating: 0, count: unichars.count)
                CTFontGetGlyphsForCharacters(ctFont, &unichars, &glyphs, unichars.count)

                let atlas = fontAtlas(for: fontName)
                atlas.insertGlyphs(glyphs.filter { $0 != 0 })
            }
        }
    }

    // MARK: - Private

    private func fontAtlas(for fontName: String) -> SlugFontAtlas {
        if let cached = fontAtlasCache[fontName] {
            return cached
        }
        let atlas = SlugFontAtlas(fontName: fontName, device: device)
        fontAtlasCache[fontName] = atlas
        let index = UInt16(orderedFontNames.count)
        fontIndexMap[fontName] = index
        orderedFontNames.append(fontName)
        return atlas
    }

    /// Returns the ordered font texture pairs for argument buffer construction.
    private var fontTexturePairs: [(curveTexture: MTLTexture, bandTexture: MTLTexture)] {
        orderedFontNames.compactMap { name in
            guard let atlas = fontAtlasCache[name],
                  let curve = atlas.curveTexture,
                  let band = atlas.bandTexture else { return nil }
            return (curve, band)
        }
    }
}

/// A character with an associated color for low-level glyph placement.
public struct ColoredCharacter {
    public var character: Character
    public var color: SIMD4<Float>

    public init(_ character: Character, color: SIMD4<Float> = SIMD4(1, 1, 1, 1)) {
        self.character = character
        self.color = color
    }
}

public extension SlugTextMeshBuilder {
    /// Builds a mesh by placing characters on a fixed grid, bypassing CoreText layout.
    /// Ideal for terminal/console rendering with monospace fonts.
    /// - Parameters:
    ///   - characters: Characters with per-character colors, laid out left-to-right, top-to-bottom.
    ///   - font: The CTFont to use for all characters.
    ///   - cellSize: The size of each grid cell in points.
    ///   - columns: Number of columns per row. Characters wrap to the next row after this many.
    @discardableResult
    func buildMesh(
        characters: [ColoredCharacter],
        font: CTFont,
        cellSize: CGSize,
        columns: Int
    ) -> Int {
        precondition(!isFinalized, "Cannot add meshes after finalize() has been called")
        precondition(columns > 0, "columns must be > 0")

        let fontName = CTFontCopyPostScriptName(font) as String
        let fontSize = Float(CTFontGetSize(font))
        let atlas = fontAtlas(for: fontName)

        // Convert all characters to glyphs and prepopulate atlas
        var unichars: [UniChar] = []
        for cc in characters {
            for unit in cc.character.utf16 {
                unichars.append(unit)
            }
        }
        var allGlyphs = [CGGlyph](repeating: 0, count: unichars.count)
        CTFontGetGlyphsForCharacters(font, &unichars, &allGlyphs, unichars.count)
        atlas.insertGlyphs(allGlyphs.filter { $0 != 0 })

        let vertexStart = allVertices.count
        let indexStart = allIndices.count
        var vertices: [GlyphVertex] = []
        var indices: [UInt32] = []

        let cellW = Float(cellSize.width)
        let cellH = Float(cellSize.height)

        var glyphIdx = 0
        for (charIdx, cc) in characters.enumerated() {
            let col = charIdx % columns
            let row = charIdx / columns
            let posX = Float(col) * cellW
            let posY = -Float(row) * cellH  // top-to-bottom

            // Get the glyph for this character (handle multi-unit characters)
            let unitCount = cc.character.utf16.count
            let glyph = allGlyphs[glyphIdx]
            glyphIdx += unitCount

            guard glyph != 0 else { continue }
            let info = atlas.glyphInfo(for: glyph)
            guard !info.isEmpty else { continue }

            let margin: Float = 0.02
            let ex0 = info.xMin - margin
            let ex1 = info.xMax + margin
            let ey0 = info.yMin - margin
            let ey1 = info.yMax + margin

            let px0 = ex0 * fontSize
            let py0 = ey0 * fontSize
            let px1 = ex1 * fontSize
            let py1 = ey1 * fontSize

            let glocX = UInt32(info.bandTexX)
            let glocY = UInt32(info.bandTexY)
            let texZPacked = glocX | (glocY << 16)
            let texZ = Float(bitPattern: texZPacked)

            let bmaxX = UInt32(info.numVertBands - 1)
            let bmaxY = UInt32(info.numHorizBands - 1)
            let texWPacked = bmaxX | (bmaxY << 16)
            let texW = Float(bitPattern: texWPacked)

            let band = SIMD4<Float>(info.bandScaleX, info.bandScaleY, info.bandOffsetX, info.bandOffsetY)
            let invScale = 1.0 / fontSize
            let invJacobian = SIMD4<Float>(invScale, 0, 0, invScale)

            let corners: [(px: Float, py: Float, ex: Float, ey: Float)] = [
                (px0, py0, ex0, ey0),
                (px1, py0, ex1, ey0),
                (px1, py1, ex1, ey1),
                (px0, py1, ex0, ey1)
            ]

            let baseIndex = UInt32(vertices.count)
            for corner in corners {
                let norm = simd_normalize(SIMD2<Float>(corner.ex, corner.ey))
                vertices.append(GlyphVertex(
                    posAndNorm: SIMD4(posX + corner.px, posY + corner.py, norm.x, norm.y),
                    texAndAtlasOffsets: SIMD4(corner.ex, corner.ey, texZ, texW),
                    invJacobian: invJacobian,
                    bandTransform: band,
                    color: cc.color,
                    indices: SIMD2<UInt32>(
                        UInt32(fontIndexMap[fontName] ?? 0),
                        UInt32(pendingMeshes.count)
                    )
                ))
            }
            indices.append(baseIndex)
            indices.append(baseIndex + 1)
            indices.append(baseIndex + 2)
            indices.append(baseIndex)
            indices.append(baseIndex + 2)
            indices.append(baseIndex + 3)
        }

        guard !vertices.isEmpty else { return appendEmptyMesh() }

        let globalVertexOffset = UInt32(allVertices.count)
        allVertices.append(contentsOf: vertices)
        allIndices.append(contentsOf: indices.map { $0 + globalVertexOffset })

        let totalWidth = Float(columns) * cellW
        let totalHeight = Float((characters.count + columns - 1) / columns) * cellH
        let bounds = CGRect(x: 0, y: CGFloat(-totalHeight), width: CGFloat(totalWidth), height: CGFloat(totalHeight))

        let index = pendingMeshes.count
        pendingMeshes.append(PendingMesh(
            vertexBufferOffset: vertexStart * MemoryLayout<GlyphVertex>.stride,
            indexBufferOffset: indexStart * MemoryLayout<UInt32>.stride,
            indexCount: indices.count,
            bounds: bounds
        ))
        return index
    }

    /// Queues a text mesh to be built. Call `finalize()` after adding all meshes.
    @discardableResult
    func buildMesh(
        string: String,
        fontName: String,
        fontSize: CGFloat = 12.0,
        maximumSize: CGSize = defaultMaximumSize
    ) -> Int {
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font
        ]
        let attributedString = NSAttributedString(string: string, attributes: attributes)
        return buildMesh(attributedString: attributedString, maximumSize: maximumSize)
    }

    /// Builds a mesh from a SwiftUI AttributedString with an explicit font.
    /// The font is applied uniformly; colors from the AttributedString are preserved.
    @discardableResult
    func buildMesh(
        attributedString: AttributedString,
        font: CTFont,
        maximumSize: CGSize = defaultMaximumSize
    ) -> Int {
        let result = NSMutableAttributedString(attributedString)
        let fullRange = NSRange(location: 0, length: result.length)
        result.addAttribute(.font, value: font, range: fullRange)
        for run in attributedString.runs {
            let nsRange = NSRange(run.range, in: attributedString)
            if let swiftUIColor = run.foregroundColor {
                #if canImport(AppKit)
                result.addAttribute(.foregroundColor, value: NSColor(swiftUIColor), range: nsRange)
                #elseif canImport(UIKit)
                result.addAttribute(.foregroundColor, value: UIColor(swiftUIColor), range: nsRange)
                #endif
            }
        }
        return buildMesh(attributedString: result, maximumSize: maximumSize)
    }

    @discardableResult
    func buildMesh(
        attributedString: AttributedString,
        maximumSize: CGSize = defaultMaximumSize
    ) -> Int {
        // SwiftUI AttributedString uses different keys than NSAttributedString.
        // Colors must be manually converted; fonts don't survive conversion.
        // For fonts, use the buildMesh(string:fontName:fontSize:) overload
        // or pass NSAttributedString directly.
        let result = NSMutableAttributedString(attributedString)
        for run in attributedString.runs {
            let nsRange = NSRange(run.range, in: attributedString)
            if let swiftUIColor = run.foregroundColor {
                #if canImport(AppKit)
                result.addAttribute(.foregroundColor, value: NSColor(swiftUIColor), range: nsRange)
                #elseif canImport(UIKit)
                result.addAttribute(.foregroundColor, value: UIColor(swiftUIColor), range: nsRange)
                #endif
            }
        }
        return buildMesh(attributedString: result, maximumSize: maximumSize)
    }
}
