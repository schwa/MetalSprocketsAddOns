// SlugTextMeshBuilder + SlugScene + SlugTextMesh + SlugError tests.
// Pure-logic tests that exercise mesh building, finalization, and error paths
// without rendering. Uses CoreText system fonts so no external assets are needed.

import CoreGraphics
import CoreText
import Foundation
import Metal
@testable import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import MetalSupport
import simd
import SwiftUI
import Testing

// MARK: - Helpers

@MainActor
private func helveticaFont(size: CGFloat = 24) -> CTFont {
    CTFontCreateWithName("Helvetica" as CFString, size, nil)
}

@MainActor
private func makeAttributed(_ string: String, fontSize: CGFloat = 24, color: CGColor? = nil) -> NSAttributedString {
    let font = helveticaFont(size: fontSize)
    var attrs: [NSAttributedString.Key: Any] = [.font: font]
    if let color {
        attrs[.foregroundColor] = color
    }
    return NSAttributedString(string: string, attributes: attrs)
}

// MARK: - Basic mesh building

@Test
@MainActor
func testSlugTextMeshBuilder_singleString() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let builder = SlugTextMeshBuilder(device: device)

    let index = builder.buildMesh(attributedString: makeAttributed("Hello"))
    #expect(index == 0)

    let scene = try builder.finalize()
    #expect(scene.meshCount == 1)
    #expect(scene.meshes.count == 1)
    #expect(scene.totalIndexCount > 0)
    #expect(scene.bufferStorage.totalIndexCount == scene.totalIndexCount)

    // Bounds should be non-empty for a non-empty string with visible glyphs.
    let mesh = scene.meshes[0]
    #expect(mesh.indexCount > 0)
    #expect(mesh.bounds.width > 0)
    #expect(mesh.bounds.height > 0)
}

@Test
@MainActor
func testSlugTextMeshBuilder_multipleStrings_indexedInOrder() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let builder = SlugTextMeshBuilder(device: device)

    let i0 = builder.buildMesh(attributedString: makeAttributed("First"))
    let i1 = builder.buildMesh(attributedString: makeAttributed("Second"))
    let i2 = builder.buildMesh(attributedString: makeAttributed("Third"))

    #expect(i0 == 0)
    #expect(i1 == 1)
    #expect(i2 == 2)

    let scene = try builder.finalize()
    #expect(scene.meshCount == 3)

    // All meshes share the same buffer storage.
    #expect(scene.meshes[0].bufferStorage === scene.meshes[1].bufferStorage)
    #expect(scene.meshes[1].bufferStorage === scene.meshes[2].bufferStorage)

    // Vertex offsets are monotonically non-decreasing.
    #expect(scene.meshes[0].vertexBufferOffset <= scene.meshes[1].vertexBufferOffset)
    #expect(scene.meshes[1].vertexBufferOffset <= scene.meshes[2].vertexBufferOffset)
}

@Test
@MainActor
func testSlugTextMeshBuilder_emptyString_producesEmptyMesh() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let builder = SlugTextMeshBuilder(device: device)

    // The builder needs at least one non-empty mesh for finalize() to succeed,
    // so add a real string first plus an empty one.
    _ = builder.buildMesh(attributedString: makeAttributed("X"))
    let emptyIndex = builder.buildMesh(attributedString: makeAttributed(""))
    #expect(emptyIndex == 1)

    let scene = try builder.finalize()
    #expect(scene.meshCount == 2)
    #expect(scene.meshes[1].indexCount == 0)
    #expect(scene.meshes[1].bounds == .zero)
}

@Test
@MainActor
func testSlugTextMeshBuilder_whitespaceOnly_producesEmptyMesh() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let builder = SlugTextMeshBuilder(device: device)

    _ = builder.buildMesh(attributedString: makeAttributed("X"))
    let wsIndex = builder.buildMesh(attributedString: makeAttributed("   "))

    let scene = try builder.finalize()
    // Whitespace glyphs have no path → contribute zero indices.
    #expect(scene.meshes[wsIndex].indexCount == 0)
}

// MARK: - Error paths

@Test
@MainActor
func testSlugTextMeshBuilder_finalizeWithNoMeshes_throws() {
    let device = _MTLCreateSystemDefaultDevice()
    let builder = SlugTextMeshBuilder(device: device)

    #expect(throws: SlugError.self) {
        try builder.finalize()
    }
}

@Test
@MainActor
func testSlugError_descriptions() {
    #expect(SlugError.bufferCreationFailed("vertex").description.contains("vertex"))
    #expect(SlugError.noMeshes.description.contains("No meshes"))
}

// MARK: - Color extraction

@Test
@MainActor
func testSlugTextMeshBuilder_colorAttributePropagatesToVertices() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let builder = SlugTextMeshBuilder(device: device)

    // Bright red foreground.
    let red = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
    _ = builder.buildMesh(attributedString: makeAttributed("A", color: red))

    let scene = try builder.finalize()
    let mesh = scene.meshes[0]
    #expect(mesh.indexCount > 0)

    // Read back the first vertex's color.
    let vertexBuffer = mesh.vertexBuffer
    let ptr = vertexBuffer.contents()
        .advanced(by: mesh.vertexBufferOffset)
        .assumingMemoryBound(to: GlyphVertex.self)
    let firstColor = ptr[0].color

    // Red component dominant, green and blue near zero.
    #expect(firstColor.x > 0.5)
    #expect(firstColor.y < 0.1)
    #expect(firstColor.z < 0.1)
    #expect(firstColor.w > 0.5)
}

// MARK: - FontAtlasCache reuse

@Test
@MainActor
func testSlugTextMeshBuilder_fontAtlasCache_isShareable() throws {
    let device = _MTLCreateSystemDefaultDevice()

    // First builder populates atlases for Helvetica.
    let builder1 = SlugTextMeshBuilder(device: device)
    _ = builder1.buildMesh(attributedString: makeAttributed("Cache me"))
    _ = try builder1.finalize()
    let cache = builder1.sharedFontAtlasCache
    #expect(!cache.cache.isEmpty)
    #expect(!cache.orderedFontNames.isEmpty)

    // Second builder receives the populated cache.
    let builder2 = SlugTextMeshBuilder(device: device, fontAtlasCache: cache)
    _ = builder2.buildMesh(attributedString: makeAttributed("Another"))
    let scene2 = try builder2.finalize()
    #expect(scene2.meshCount == 1)
    #expect(scene2.fontTexturePairs.count >= 1)
}

// MARK: - Grid layout (buildMesh(characters:font:cellSize:columns:))

@Test
@MainActor
func testSlugTextMeshBuilder_gridLayout_basic() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let builder = SlugTextMeshBuilder(device: device)

    let chars: [ColoredCharacter] = "ABCDEF".map { ColoredCharacter($0, color: SIMD4<Float>(1, 1, 1, 1)) }
    _ = builder.buildMesh(
        characters: chars,
        font: helveticaFont(size: 12),
        cellSize: CGSize(width: 8, height: 16),
        columns: 3
    )

    let scene = try builder.finalize()
    #expect(scene.meshCount == 1)
    let mesh = scene.meshes[0]
    // 6 chars * 6 indices each = 36 indices.
    #expect(mesh.indexCount == 36)

    // Bounds: 3 columns * 8 = 24 wide, 2 rows * 16 = 32 tall.
    #expect(mesh.bounds.width == 24)
    #expect(mesh.bounds.height == 32)
}

@Test
@MainActor
func testSlugTextMeshBuilder_gridLayout_perCharacterColors() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let builder = SlugTextMeshBuilder(device: device)

    let chars: [ColoredCharacter] = [
        ColoredCharacter("R", color: SIMD4<Float>(1, 0, 0, 1)),
        ColoredCharacter("G", color: SIMD4<Float>(0, 1, 0, 1)),
        ColoredCharacter("B", color: SIMD4<Float>(0, 0, 1, 1))
    ]
    _ = builder.buildMesh(
        characters: chars,
        font: helveticaFont(size: 16),
        cellSize: CGSize(width: 12, height: 20),
        columns: 3
    )
    let scene = try builder.finalize()
    let mesh = scene.meshes[0]

    // First quad (4 vertices) belongs to "R".
    let ptr = mesh.vertexBuffer.contents()
        .advanced(by: mesh.vertexBufferOffset)
        .assumingMemoryBound(to: GlyphVertex.self)
    #expect(ptr[0].color.x > 0.5)
    #expect(ptr[0].color.y < 0.1)
    // Fifth vertex belongs to "G".
    #expect(ptr[4].color.y > 0.5)
    #expect(ptr[4].color.x < 0.1)
    // Ninth vertex belongs to "B".
    #expect(ptr[8].color.z > 0.5)
}

// MARK: - SwiftUI AttributedString overload

// Grayscale CGColor path: NSAttributedString carrying a 2-component (gray + alpha)
// CGColor exercises the `n >= 2` else branch in the foreground-color extraction.
@Test
@MainActor
func testSlugTextMeshBuilder_grayscaleForegroundColor() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let builder = SlugTextMeshBuilder(device: device)

    let grayColorSpace = CGColorSpaceCreateDeviceGray()
    let grayColor = CGColor(colorSpace: grayColorSpace, components: [0.6, 1.0])!

    let font = helveticaFont()
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: grayColor
    ]
    let attr = NSAttributedString(string: "G", attributes: attrs)
    _ = builder.buildMesh(attributedString: attr)

    let scene = try builder.finalize()
    let mesh = scene.meshes[0]
    let ptr = mesh.vertexBuffer.contents()
        .advanced(by: mesh.vertexBufferOffset)
        .assumingMemoryBound(to: GlyphVertex.self)
    // Grayscale gets broadcast to RGB so all three channels should match.
    let c = ptr[0].color
    #expect(abs(c.x - c.y) < 0.01)
    #expect(abs(c.y - c.z) < 0.01)
    #expect(c.w > 0.5)
}

// SwiftUI AttributedString overload that does NOT take an explicit font.
// Per the implementation comment fonts don't survive conversion, but it should
// still build a mesh (with whatever default the system provides).
@Test
@MainActor
func testSlugTextMeshBuilder_swiftUIAttributedString_noExplicitFont() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let builder = SlugTextMeshBuilder(device: device)

    var attr = AttributedString("Z")
    attr.foregroundColor = .red
    // We need at least one mesh with a font to give finalize() something to work with,
    // so seed a small one first.
    _ = builder.buildMesh(attributedString: makeAttributed("seed"))
    _ = builder.buildMesh(attributedString: attr)

    let scene = try builder.finalize()
    #expect(scene.meshCount == 2)
}

@Test
@MainActor
func testSlugTextMeshBuilder_swiftUIAttributedString_withFont() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let builder = SlugTextMeshBuilder(device: device)

    var attr = AttributedString("Hi")
    attr.foregroundColor = .green
    _ = builder.buildMesh(attributedString: attr, font: helveticaFont(size: 20))

    let scene = try builder.finalize()
    #expect(scene.meshCount == 1)
    #expect(scene.meshes[0].indexCount > 0)
}

// MARK: - Prepopulation

@Test
@MainActor
func testSlugTextMeshBuilder_prepopulateGlyphs_swiftUIAttributedString() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let builder = SlugTextMeshBuilder(device: device)

    var attr = AttributedString("Lorem ipsum")
    attr.font = .system(size: 16)
    builder.prepopulateGlyphs(from: [attr])

    // Now actually build a mesh — should reuse the preloaded glyphs.
    _ = builder.buildMesh(attributedString: makeAttributed("Lorem"))
    let scene = try builder.finalize()
    #expect(scene.meshCount == 1)
    #expect(!scene.fontTexturePairs.isEmpty)
}

@Test
@MainActor
func testSlugTextMeshBuilder_prepopulateGlyphs_nsAttributedString() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let builder = SlugTextMeshBuilder(device: device)

    builder.prepopulateGlyphs(from: [makeAttributed("Pre populate")])
    _ = builder.buildMesh(attributedString: makeAttributed("Pre"))
    let scene = try builder.finalize()
    #expect(scene.meshCount == 1)
}

// MARK: - Convenience overload (string:fontName:fontSize:)

@Test
@MainActor
func testSlugTextMeshBuilder_multiLineText_producesNonZeroBounds() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let builder = SlugTextMeshBuilder(device: device)

    // Force multi-line layout via newline + a tight max width.
    let attr = makeAttributed("Line one\nLine two\nLine three")
    _ = builder.buildMesh(attributedString: attr)
    let scene = try builder.finalize()
    #expect(scene.meshCount == 1)
    let mesh = scene.meshes[0]
    #expect(mesh.indexCount > 0)
    // Multiple lines means the mesh is taller than a single-line render.
    #expect(mesh.bounds.height > 24)  // > one line at 24pt
}

@Test
@MainActor
func testSlugTextMeshBuilder_constrainedMaxWidth_wrapsLines() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let builder = SlugTextMeshBuilder(device: device)

    // Long string with a narrow maximum size forces CoreText to wrap.
    let attr = makeAttributed("The quick brown fox jumps over the lazy dog")
    _ = builder.buildMesh(
        attributedString: attr,
        maximumSize: CGSize(width: 80, height: CGFloat.greatestFiniteMagnitude)
    )
    let scene = try builder.finalize()
    #expect(scene.meshes[0].indexCount > 0)
}

@Test
@MainActor
func testSlugTextMeshBuilder_buildFromStringAndFontName() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let builder = SlugTextMeshBuilder(device: device)

    _ = builder.buildMesh(string: "Quick", fontName: "Helvetica", fontSize: 18)
    let scene = try builder.finalize()
    #expect(scene.meshCount == 1)
    #expect(scene.meshes[0].indexCount > 0)
}

// MARK: - SlugScene model matrices

@Test
@MainActor
func testSlugScene_modelMatrices_areIdentityByDefault() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let builder = SlugTextMeshBuilder(device: device)
    _ = builder.buildMesh(attributedString: makeAttributed("X"))
    _ = builder.buildMesh(attributedString: makeAttributed("Y"))
    let scene = try builder.finalize()

    let identity = float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))
    for matrix in scene.modelMatrices {
        #expect(matrix == identity)
    }
}

@Test
@MainActor
func testSlugScene_withModelMatrices_boundsCheckedWriteAndRead() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let builder = SlugTextMeshBuilder(device: device)
    _ = builder.buildMesh(attributedString: makeAttributed("Hello"))
    let scene = try builder.finalize()

    let translation = float4x4(translation: SIMD3<Float>(10, 20, 30))
    scene.withModelMatrices { span in
        span[0] = translation
    }
    #expect(scene.modelMatrices[0] == translation)
}

// MARK: - SlugFrameConstants

@Test
@MainActor
func testSlugFrameConstants_initFromCGSize() {
    let mvp = float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))
    let constants = SlugFrameConstants(viewProjectionMatrix: mvp, viewportSize: CGSize(width: 800, height: 600))
    #expect(constants.viewportSize.x == 800)
    #expect(constants.viewportSize.y == 600)
}

@Test
@MainActor
func testSlugFrameConstants_initFromSIMD() {
    let mvp = float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))
    let constants = SlugFrameConstants(viewProjectionMatrix: mvp, viewportSize: SIMD2<Float>(1_024, 768))
    #expect(constants.viewportSize == SIMD2<Float>(1_024, 768))
}

// MARK: - GlyphVertex descriptor

@Test
@MainActor
func testGlyphVertex_descriptor_layout() {
    let desc = GlyphVertex.descriptor
    #expect(desc.attributes[0].format == .float4)
    #expect(desc.attributes[0].offset == 0)
    #expect(desc.attributes[4].format == .float4)
    #expect(desc.attributes[4].offset == 64)
    #expect(desc.attributes[5].format == .uint2)
    #expect(desc.attributes[5].offset == 80)
    #expect(desc.layouts[0]?.stride == MemoryLayout<GlyphVertex>.stride)
    #expect(desc.layouts[0]?.stepFunction == .perVertex)
}

// MARK: - ColoredCharacter

@Test
func testColoredCharacter_init() {
    let cc = ColoredCharacter("A")
    #expect(cc.character == "A")
    #expect(cc.color == SIMD4<Float>(1, 1, 1, 1))

    let red = ColoredCharacter("R", color: SIMD4<Float>(1, 0, 0, 1))
    #expect(red.character == "R")
    #expect(red.color == SIMD4<Float>(1, 0, 0, 1))
}
