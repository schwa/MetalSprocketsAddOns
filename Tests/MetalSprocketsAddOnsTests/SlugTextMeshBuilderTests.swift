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

// MARK: - FontAtlasCache reuse

// Overload pair used to observe a type's `Sendable` conformance at runtime: the constrained
// overload wins whenever the conformance exists. `is any Sendable.Type` cannot be used because
// Sendable is a marker protocol.
private func conformsToSendable<T: Sendable>(_: T.Type) -> Bool { true }
private func conformsToSendable<T>(_: T.Type) -> Bool { false }

@Test
func testFontAtlasCache_isNotSendable() {
    // FontAtlasCache holds mutable, unsynchronized SlugFontAtlas instances, so it must not
    // advertise cross-isolation transfer.
    #expect(conformsToSendable(FontAtlasCache.self) == false)
    #expect(conformsToSendable(Int.self) == true)
}

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

// MARK: - SwiftUI AttributedString overload

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
    for index in 0..<scene.meshCount {
        #expect(scene.modelMatrix(at: index) == identity)
    }
}

@Test
@MainActor
func testSlugScene_modelMatrixAccess_isScopedNotEscaping() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let builder = SlugTextMeshBuilder(device: device)
    _ = builder.buildMesh(attributedString: makeAttributed("Scoped"))
    let scene = try builder.finalize()

    // The only public views of the model matrices are scoped: a bounds-checked span for writes
    // and a by-value read. Neither hands out a pointer that can outlive the scene.
    #expect(scene.withModelMatrices { $0.count } == scene.meshCount)

    // SlugScene owns unsynchronized GPU storage and non-Sendable MTLTextures.
    #expect(conformsToSendable(SlugScene.self) == false)

    let scale = float4x4(diagonal: SIMD4<Float>(2, 2, 2, 1))
    scene.withModelMatrices { span in
        span[0] = scale
    }
    #expect(scene.modelMatrix(at: 0) == scale)
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
    #expect(scene.modelMatrix(at: 0) == translation)
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

// MARK: - Representation tests (vertex descriptor)
//
// The tests in this section and in "Representation tests (vertex buffer contents)" below
// deliberately pin the GPU representation: the interleaved `GlyphVertex`
// layout and the vertex order the builder writes. They break when that representation
// changes, which is the point — the shaders and vertex descriptor depend on it. Everything
// else in this file is written against observable behaviour (mesh/index counts, bounds), and
// colours reaching the GPU are covered by the golden render in
// `testSlugTextRenderPipeline_gridLayoutColoredCharacters`.

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

// MARK: - Representation tests (vertex buffer contents)

/// A vertex of `mesh`, read straight out of the shared vertex buffer.
@MainActor
private func vertex(of mesh: SlugTextMesh, at vertexIndex: Int = 0) -> GlyphVertex {
    mesh.vertexBuffer.contents()
        .advanced(by: mesh.vertexBufferOffset)
        .assumingMemoryBound(to: GlyphVertex.self)[vertexIndex]
}

@Test
@MainActor
func testSlugTextMeshBuilder_colorAttributePropagatesToVertices() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let builder = SlugTextMeshBuilder(device: device)

    let red = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
    _ = builder.buildMesh(attributedString: makeAttributed("A", color: red))

    let scene = try builder.finalize()
    let mesh = scene.meshes[0]
    #expect(mesh.indexCount > 0)

    let color = vertex(of: mesh).color
    #expect(color.x > 0.5)
    #expect(color.y < 0.1)
    #expect(color.z < 0.1)
    #expect(color.w > 0.5)
}

// Grayscale CGColor path: NSAttributedString carrying a 2-component (gray + alpha)
// CGColor exercises the `n >= 2` else branch in the foreground-color extraction.
@Test
@MainActor
func testSlugTextMeshBuilder_grayscaleForegroundColor() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let builder = SlugTextMeshBuilder(device: device)

    let grayColorSpace = CGColorSpaceCreateDeviceGray()
    let grayColor = CGColor(colorSpace: grayColorSpace, components: [0.6, 1.0])!
    let attrs: [NSAttributedString.Key: Any] = [
        .font: helveticaFont(),
        .foregroundColor: grayColor
    ]
    _ = builder.buildMesh(attributedString: NSAttributedString(string: "G", attributes: attrs))

    let scene = try builder.finalize()
    // Grayscale gets broadcast to RGB so all three channels should match.
    let color = vertex(of: scene.meshes[0]).color
    #expect(abs(color.x - color.y) < 0.01)
    #expect(abs(color.y - color.z) < 0.01)
    #expect(color.w > 0.5)
}

// One quad (4 vertices) per character, in the order the characters were given.
@Test
@MainActor
func testSlugTextMeshBuilder_gridLayout_perCharacterColors() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let builder = SlugTextMeshBuilder(device: device)

    let characters: [ColoredCharacter] = [
        ColoredCharacter("R", color: SIMD4<Float>(1, 0, 0, 1)),
        ColoredCharacter("G", color: SIMD4<Float>(0, 1, 0, 1)),
        ColoredCharacter("B", color: SIMD4<Float>(0, 0, 1, 1))
    ]
    _ = builder.buildMesh(
        characters: characters,
        font: helveticaFont(size: 16),
        cellSize: CGSize(width: 12, height: 20),
        columns: 3
    )
    let scene = try builder.finalize()
    let mesh = scene.meshes[0]

    #expect(vertex(of: mesh, at: 0).color.x > 0.5)
    #expect(vertex(of: mesh, at: 0).color.y < 0.1)
    #expect(vertex(of: mesh, at: 4).color.y > 0.5)
    #expect(vertex(of: mesh, at: 4).color.x < 0.1)
    #expect(vertex(of: mesh, at: 8).color.z > 0.5)
}
