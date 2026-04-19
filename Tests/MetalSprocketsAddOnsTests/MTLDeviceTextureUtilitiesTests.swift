// Tests for MTLDevice texture utilities (cross→cube conversion and SwiftUI view→texture).

import CoreGraphics
import Metal
import MetalSprockets
@testable import MetalSprocketsAddOns
import MetalSprocketsSupport
import MetalSupport
import simd
import SwiftUI
import Testing

// MARK: - Cross → Cube

@Test
@MainActor
func testMakeTextureCubeFromCrossTexture_facesCopied() throws {
    let device = _MTLCreateSystemDefaultDevice()

    // Build a 4×3 cell "cross" texture; each cell is a single solid color so we can
    // identify it by reading back a single pixel from the corresponding cube face.
    //
    // Cross layout (in cells, +Y axis = down because the texture origin is top-left):
    //         [5]
    //     [1] [4] [0] [5]
    //         [2]
    //
    // The implementation maps cell origins → cube face slices via:
    //   origins[slice] = [2,1], [0,1], [1,0], [1,2], [1,1], [3,1]
    let cellSize = 8
    let crossWidth = cellSize * 4
    let crossHeight = cellSize * 3

    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm,
        width: crossWidth,
        height: crossHeight,
        mipmapped: false
    )
    descriptor.usage = [.shaderRead]
    descriptor.storageMode = .shared
    let crossTexture = try device.makeTexture(descriptor: descriptor)
        .orThrow(.resourceCreationFailure("Failed to create cross texture"))

    // Solid color per cube face slice.
    // slice 0 → cell (2,1), slice 1 → (0,1), slice 2 → (1,0), slice 3 → (1,2), slice 4 → (1,1), slice 5 → (3,1)
    let cellColors: [(SIMD2<Int>, SIMD4<UInt8>)] = [
        ([2, 1], [255, 0, 0, 255]),     // slice 0 - red
        ([0, 1], [0, 255, 0, 255]),     // slice 1 - green
        ([1, 0], [0, 0, 255, 255]),     // slice 2 - blue
        ([1, 2], [255, 255, 0, 255]),   // slice 3 - yellow
        ([1, 1], [255, 0, 255, 255]),   // slice 4 - magenta
        ([3, 1], [0, 255, 255, 255])    // slice 5 - cyan
    ]

    var pixels = [UInt8](repeating: 0, count: crossWidth * crossHeight * 4)
    for (cell, color) in cellColors {
        let originX = cell.x * cellSize
        let originY = cell.y * cellSize
        for y in 0..<cellSize {
            for x in 0..<cellSize {
                let idx = ((originY + y) * crossWidth + (originX + x)) * 4
                pixels[idx + 0] = color.x
                pixels[idx + 1] = color.y
                pixels[idx + 2] = color.z
                pixels[idx + 3] = color.w
            }
        }
    }
    crossTexture.replace(
        region: MTLRegionMake2D(0, 0, crossWidth, crossHeight),
        mipmapLevel: 0,
        withBytes: pixels,
        bytesPerRow: crossWidth * 4
    )

    // Run the conversion.
    let cube = try device.makeTextureCubeFromCrossTexture(texture: crossTexture)

    #expect(cube.textureType == .typeCube)
    #expect(cube.width == cellSize)
    #expect(cube.height == cellSize)

    // Read back the center pixel of each cube face slice and confirm the color matches.
    for (slice, expected) in cellColors.map(\.1).enumerated() {
        var readback = [UInt8](repeating: 0, count: cellSize * cellSize * 4)
        cube.getBytes(
            &readback,
            bytesPerRow: cellSize * 4,
            bytesPerImage: cellSize * cellSize * 4,
            from: MTLRegionMake2D(0, 0, cellSize, cellSize),
            mipmapLevel: 0,
            slice: slice
        )
        // Sample center pixel.
        let cx = cellSize / 2
        let cy = cellSize / 2
        let off = (cy * cellSize + cx) * 4
        let actual = SIMD4<UInt8>(readback[off + 0], readback[off + 1], readback[off + 2], readback[off + 3])
        #expect(actual == expected, "Slice \(slice) expected \(expected) but got \(actual)")
    }
}

// MARK: - SwiftUI View → Texture

@Test
@MainActor
func testMakeTextureFromSwiftUIView() throws {
    let device = _MTLCreateSystemDefaultDevice()

    let view = ZStack {
        Color.blue
        Text("M").font(.system(size: 40)).foregroundStyle(.white)
    }
    .frame(width: 64, height: 64)

    let texture = try device.makeTexture(content: view)

    #expect(texture.width > 0)
    #expect(texture.height > 0)
}
