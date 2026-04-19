// SlugFontAtlas tests.
// Exercise the (internal) atlas: glyph insertion, caching, texture upload,
// QuadBezier predicates, and the empty-glyph paths.

import CoreGraphics
import CoreText
import Foundation
import Metal
@testable import MetalSprocketsAddOns
import MetalSprocketsSupport
import MetalSupport
import simd
import Testing

// MARK: - QuadBezier predicates

@Test
func testQuadBezier_minMaxBounds() {
    let curve = SlugFontAtlas.QuadBezier(
        p0: SIMD2<Float>(0, 0),
        p1: SIMD2<Float>(5, 10),
        p2: SIMD2<Float>(2, -3)
    )
    #expect(curve.minX == 0)
    #expect(curve.maxX == 5)
    #expect(curve.minY == -3)
    #expect(curve.maxY == 10)
}

@Test
func testQuadBezier_isStraightHorizontal_true() {
    // p0.y ≈ p2.y AND p1.y ≈ midpoint
    let curve = SlugFontAtlas.QuadBezier(
        p0: SIMD2<Float>(0, 5),
        p1: SIMD2<Float>(2, 5),
        p2: SIMD2<Float>(4, 5)
    )
    #expect(curve.isStraightHorizontal)
    #expect(!curve.isStraightVertical)
}

@Test
func testQuadBezier_isStraightVertical_true() {
    let curve = SlugFontAtlas.QuadBezier(
        p0: SIMD2<Float>(3, 0),
        p1: SIMD2<Float>(3, 5),
        p2: SIMD2<Float>(3, 10)
    )
    #expect(curve.isStraightVertical)
    #expect(!curve.isStraightHorizontal)
}

@Test
func testQuadBezier_curved_isNeitherStraightHorizontalNorVertical() {
    let curve = SlugFontAtlas.QuadBezier(
        p0: SIMD2<Float>(0, 0),
        p1: SIMD2<Float>(5, 10),
        p2: SIMD2<Float>(10, 0)
    )
    #expect(!curve.isStraightHorizontal)
    #expect(!curve.isStraightVertical)
}

// MARK: - GlyphInfo.empty

@Test
func testGlyphInfo_empty_isFlaggedEmpty() {
    let info = SlugFontAtlas.GlyphInfo.empty
    #expect(info.isEmpty)
    #expect(info.curveCount == 0)
    #expect(info.advanceWidth == 0)
}

@Test
func testGlyphInfo_nonEmpty_isFlaggedNonEmpty() {
    let info = SlugFontAtlas.GlyphInfo(
        advanceWidth: 0.5,
        xMin: 0,
        yMin: 0,
        xMax: 1,
        yMax: 1,
        curveTexStart: 0,
        curveCount: 4,
        bandTexX: 0,
        bandTexY: 0,
        numHorizBands: 8,
        numVertBands: 8,
        bandScaleX: 1,
        bandScaleY: 1,
        bandOffsetX: 0,
        bandOffsetY: 0
    )
    #expect(!info.isEmpty)
}

// MARK: - Atlas glyph insertion + lookup

@MainActor
private func glyphsFor(_ string: String, font: CTFont) -> [CGGlyph] {
    var unichars = Array(string.utf16)
    var glyphs = [CGGlyph](repeating: 0, count: unichars.count)
    CTFontGetGlyphsForCharacters(font, &unichars, &glyphs, unichars.count)
    return glyphs
}

@Test
@MainActor
func testSlugFontAtlas_insertGlyphs_populatesCacheAndTextures() {
    let device = _MTLCreateSystemDefaultDevice()
    let atlas = SlugFontAtlas(fontName: "Helvetica", device: device)

    // Before insertion, glyphs return empty info.
    let preInfo = atlas.glyphInfo(for: 1)
    #expect(preInfo.isEmpty)
    #expect(atlas.curveTexture == nil)
    #expect(atlas.bandTexture == nil)

    // Insert the glyphs for "A" — a glyph with multiple bezier segments.
    let font = CTFontCreateWithName("Helvetica" as CFString, 1.0, nil)
    let glyphs = glyphsFor("A", font: font)
    #expect(!glyphs.isEmpty)

    atlas.insertGlyphs(glyphs)

    // After insertion: textures created, glyph cached with non-empty info.
    #expect(atlas.curveTexture != nil)
    #expect(atlas.bandTexture != nil)
    let info = atlas.glyphInfo(for: glyphs[0])
    #expect(!info.isEmpty)
    #expect(info.curveCount > 0)
    #expect(info.advanceWidth > 0)
    #expect(info.xMax > info.xMin)
    #expect(info.yMax > info.yMin)
    #expect(info.numHorizBands == 8)
    #expect(info.numVertBands == 8)
}

@Test
@MainActor
func testSlugFontAtlas_insertGlyphs_isIdempotent() {
    let device = _MTLCreateSystemDefaultDevice()
    let atlas = SlugFontAtlas(fontName: "Helvetica", device: device)
    let font = CTFontCreateWithName("Helvetica" as CFString, 1.0, nil)
    let glyphs = glyphsFor("X", font: font)

    atlas.insertGlyphs(glyphs)
    let infoFirst = atlas.glyphInfo(for: glyphs[0])

    // Re-insert same glyph — should not change cached info.
    atlas.insertGlyphs(glyphs)
    let infoSecond = atlas.glyphInfo(for: glyphs[0])

    #expect(infoFirst.curveTexStart == infoSecond.curveTexStart)
    #expect(infoFirst.curveCount == infoSecond.curveCount)
    #expect(infoFirst.bandTexX == infoSecond.bandTexX)
    #expect(infoFirst.bandTexY == infoSecond.bandTexY)
}

@Test
@MainActor
func testSlugFontAtlas_whitespaceGlyph_hasZeroCurves() {
    let device = _MTLCreateSystemDefaultDevice()
    let atlas = SlugFontAtlas(fontName: "Helvetica", device: device)
    let font = CTFontCreateWithName("Helvetica" as CFString, 1.0, nil)
    // Space character has no path → curveCount == 0 but advanceWidth > 0.
    let glyphs = glyphsFor(" ", font: font)
    atlas.insertGlyphs(glyphs)

    let info = atlas.glyphInfo(for: glyphs[0])
    #expect(info.curveCount == 0)
    #expect(info.advanceWidth > 0)
}

@Test
@MainActor
func testSlugFontAtlas_complexGlyphSet_populatesCurvesAndBands() {
    // Mix of letters with curves, straight lines, and closed paths to exercise
    // multiple branches of extractQuadBeziers (move, line, quad, close, bounds).
    let device = _MTLCreateSystemDefaultDevice()
    let atlas = SlugFontAtlas(fontName: "Helvetica", device: device)
    let font = CTFontCreateWithName("Helvetica" as CFString, 1.0, nil)
    let glyphs = glyphsFor("OQRgB&@", font: font)
    atlas.insertGlyphs(glyphs)

    // All glyphs should be cached and non-empty.
    for g in glyphs {
        let info = atlas.glyphInfo(for: g)
        #expect(!info.isEmpty)
        #expect(info.curveCount > 0)
        #expect(info.numHorizBands == 8)
        #expect(info.numVertBands == 8)
    }
}

// Some PostScript / CFF fonts (e.g. Times) use cubic Bezier segments which the
// atlas converts to two quadratics via `cubicToQuadratic`. This test ensures
// that conversion path executes successfully.
@Test
@MainActor
func testSlugFontAtlas_postscriptFont_handlesCubicSegments() {
    let device = _MTLCreateSystemDefaultDevice()
    let atlas = SlugFontAtlas(fontName: "Times-Roman", device: device)
    let font = CTFontCreateWithName("Times-Roman" as CFString, 1.0, nil)
    // Times-Roman is a CFF/PostScript font on macOS; "O" has cubic outlines.
    let glyphs = glyphsFor("O", font: font)
    atlas.insertGlyphs(glyphs)

    let info = atlas.glyphInfo(for: glyphs[0])
    // Don't assert on exact curve count — just that the path was processed.
    #expect(!info.isEmpty)
    #expect(info.curveCount > 0)
}

@Test
@MainActor
func testSlugFontAtlas_multipleGlyphs_distinctCurveOffsets() {
    let device = _MTLCreateSystemDefaultDevice()
    let atlas = SlugFontAtlas(fontName: "Helvetica", device: device)
    let font = CTFontCreateWithName("Helvetica" as CFString, 1.0, nil)
    let glyphs = glyphsFor("OQ", font: font)
    atlas.insertGlyphs(glyphs)

    let infoO = atlas.glyphInfo(for: glyphs[0])
    let infoQ = atlas.glyphInfo(for: glyphs[1])
    #expect(!infoO.isEmpty)
    #expect(!infoQ.isEmpty)
    // Each glyph occupies a distinct slice of the curve texture.
    #expect(infoO.curveTexStart != infoQ.curveTexStart)
}
