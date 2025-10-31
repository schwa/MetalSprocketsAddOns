// FlatShader Unit Tests
//
// These tests render geometry using the FlatShader pipeline and verify the output.
// Tests compare rendered output against golden reference images.
//
// To run these tests:
//
//   just test-flatshader          # Run FlatShader tests (recommended)
//   just test                     # Run all tests
//   swift test --filter FlatShader  # Direct CLI

import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsSupport
import simd
import Testing
@testable import MetalSprocketsAddOns

@Test
@MainActor
func testFlatShaderWithColor() throws {
    // Define a simple quad vertex structure matching FlatShader's expectations
    struct Vertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
        var textureCoordinate: SIMD2<Float>
    }

    // Create a simple quad in normalized device coordinates
    let vertices: [Vertex] = [
        // Triangle 1
        Vertex(position: [-0.5, -0.5, 0], normal: [0, 0, 1], textureCoordinate: [0, 0]),
        Vertex(position: [0.5, -0.5, 0], normal: [0, 0, 1], textureCoordinate: [1, 0]),
        Vertex(position: [0.5, 0.5, 0], normal: [0, 0, 1], textureCoordinate: [1, 1]),
        // Triangle 2
        Vertex(position: [-0.5, -0.5, 0], normal: [0, 0, 1], textureCoordinate: [0, 0]),
        Vertex(position: [0.5, 0.5, 0], normal: [0, 0, 1], textureCoordinate: [1, 1]),
        Vertex(position: [-0.5, 0.5, 0], normal: [0, 0, 1], textureCoordinate: [0, 1]),
    ]

    // Create an identity matrix for modelViewProjection (since we're in normalized device coords)
    let modelViewProjection = matrix_identity_float4x4

    // Create a red color source
    let colorSource = ColorSource.color([1.0, 0.0, 0.0])

    // Create vertex descriptor matching FlatShader's expectations
    let vertexDescriptor = MTLVertexDescriptor()
    // position - attribute 0
    vertexDescriptor.attributes[0].format = .float3
    vertexDescriptor.attributes[0].offset = 0
    vertexDescriptor.attributes[0].bufferIndex = 0
    // normal - attribute 1
    vertexDescriptor.attributes[1].format = .float3
    vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
    vertexDescriptor.attributes[1].bufferIndex = 0
    // textureCoordinate - attribute 2
    vertexDescriptor.attributes[2].format = .float2
    vertexDescriptor.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride * 2
    vertexDescriptor.attributes[2].bufferIndex = 0
    // layout
    vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
    vertexDescriptor.layouts[0].stepFunction = .perVertex

    // Create the render pass with FlatShader
    let renderPass = try RenderPass {
        try FlatShader(modelViewProjection: modelViewProjection, textureSpecifier: colorSource) {
            Draw { encoder in
                encoder.setVertexBytes(vertices, length: MemoryLayout<Vertex>.stride * vertices.count, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
            }
        }
        .vertexDescriptor(vertexDescriptor)
    }

    // Render offscreen
    let offscreenRenderer = try OffscreenRenderer(size: CGSize(width: 400, height: 400))
    let texture = try offscreenRenderer.render(renderPass)

    // Verify the output matches the golden image
    let image = try texture.cgImage
    #expect(try image.isEqualToGoldenImage(named: "FlatShaderRed"))
}

@Test
@MainActor
func testFlatShaderWithTexture() throws {
    // Define vertex structure
    struct Vertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
        var textureCoordinate: SIMD2<Float>
    }

    // Create a simple quad
    let vertices: [Vertex] = [
        // Triangle 1
        Vertex(position: [-0.5, -0.5, 0], normal: [0, 0, 1], textureCoordinate: [0, 0]),
        Vertex(position: [0.5, -0.5, 0], normal: [0, 0, 1], textureCoordinate: [1, 0]),
        Vertex(position: [0.5, 0.5, 0], normal: [0, 0, 1], textureCoordinate: [1, 1]),
        // Triangle 2
        Vertex(position: [-0.5, -0.5, 0], normal: [0, 0, 1], textureCoordinate: [0, 0]),
        Vertex(position: [0.5, 0.5, 0], normal: [0, 0, 1], textureCoordinate: [1, 1]),
        Vertex(position: [-0.5, 0.5, 0], normal: [0, 0, 1], textureCoordinate: [0, 1]),
    ]

    // Create a simple test texture (4x4 checkerboard pattern)
    let device = _MTLCreateSystemDefaultDevice()
    let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm,
        width: 4,
        height: 4,
        mipmapped: false
    )
    textureDescriptor.usage = [.shaderRead]
    let texture = try device.makeTexture(descriptor: textureDescriptor)
        .orThrow(.resourceCreationFailure("Failed to create test texture"))

    // Fill texture with a simple pattern (blue and green checkerboard)
    var pixels: [UInt8] = []
    for y in 0..<4 {
        for x in 0..<4 {
            if (x + y) % 2 == 0 {
                pixels.append(contentsOf: [0, 0, 255, 255]) // Blue
            } else {
                pixels.append(contentsOf: [0, 255, 0, 255]) // Green
            }
        }
    }

    let region = MTLRegionMake2D(0, 0, 4, 4)
    texture.replace(region: region, mipmapLevel: 0, withBytes: pixels, bytesPerRow: 4 * 4)

    // Create texture color source
    let colorSource = ColorSource.texture2D(texture)

    // Create an identity matrix
    let modelViewProjection = matrix_identity_float4x4

    // Create vertex descriptor matching FlatShader's expectations
    let vertexDescriptor = MTLVertexDescriptor()
    vertexDescriptor.attributes[0].format = .float3
    vertexDescriptor.attributes[0].offset = 0
    vertexDescriptor.attributes[0].bufferIndex = 0
    vertexDescriptor.attributes[1].format = .float3
    vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
    vertexDescriptor.attributes[1].bufferIndex = 0
    vertexDescriptor.attributes[2].format = .float2
    vertexDescriptor.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride * 2
    vertexDescriptor.attributes[2].bufferIndex = 0
    vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
    vertexDescriptor.layouts[0].stepFunction = .perVertex

    // Create the render pass with FlatShader
    let renderPass = try RenderPass {
        try FlatShader(modelViewProjection: modelViewProjection, textureSpecifier: colorSource) {
            Draw { encoder in
                encoder.setVertexBytes(vertices, length: MemoryLayout<Vertex>.stride * vertices.count, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
            }
        }
        .vertexDescriptor(vertexDescriptor)
    }

    // Render offscreen
    let offscreenRenderer = try OffscreenRenderer(size: CGSize(width: 400, height: 400))
    let renderedTexture = try offscreenRenderer.render(renderPass)

    // Verify the output matches the golden image
    let image = try renderedTexture.cgImage
    #expect(try image.isEqualToGoldenImage(named: "FlatShaderTextured"))
}

@Test
@MainActor
func testFlatShaderWithTransform() throws {
    // Define vertex structure
    struct Vertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
        var textureCoordinate: SIMD2<Float>
    }

    // Create a simple quad
    let vertices: [Vertex] = [
        // Triangle 1
        Vertex(position: [-0.25, -0.25, 0], normal: [0, 0, 1], textureCoordinate: [0, 0]),
        Vertex(position: [0.25, -0.25, 0], normal: [0, 0, 1], textureCoordinate: [1, 0]),
        Vertex(position: [0.25, 0.25, 0], normal: [0, 0, 1], textureCoordinate: [1, 1]),
        // Triangle 2
        Vertex(position: [-0.25, -0.25, 0], normal: [0, 0, 1], textureCoordinate: [0, 0]),
        Vertex(position: [0.25, 0.25, 0], normal: [0, 0, 1], textureCoordinate: [1, 1]),
        Vertex(position: [-0.25, 0.25, 0], normal: [0, 0, 1], textureCoordinate: [0, 1]),
    ]

    // Create a rotation transform
    let rotation = simd_quatf(angle: .pi / 4, axis: [0, 0, 1]) // 45 degree rotation
    let modelViewProjection = float4x4(rotation)

    // Create a blue color source
    let colorSource = ColorSource.color([0.0, 0.0, 1.0])

    // Create vertex descriptor matching FlatShader's expectations
    let vertexDescriptor = MTLVertexDescriptor()
    vertexDescriptor.attributes[0].format = .float3
    vertexDescriptor.attributes[0].offset = 0
    vertexDescriptor.attributes[0].bufferIndex = 0
    vertexDescriptor.attributes[1].format = .float3
    vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
    vertexDescriptor.attributes[1].bufferIndex = 0
    vertexDescriptor.attributes[2].format = .float2
    vertexDescriptor.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride * 2
    vertexDescriptor.attributes[2].bufferIndex = 0
    vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
    vertexDescriptor.layouts[0].stepFunction = .perVertex

    // Create the render pass with FlatShader
    let renderPass = try RenderPass {
        try FlatShader(modelViewProjection: modelViewProjection, textureSpecifier: colorSource) {
            Draw { encoder in
                encoder.setVertexBytes(vertices, length: MemoryLayout<Vertex>.stride * vertices.count, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
            }
        }
        .vertexDescriptor(vertexDescriptor)
    }

    // Render offscreen
    let offscreenRenderer = try OffscreenRenderer(size: CGSize(width: 400, height: 400))
    let texture = try offscreenRenderer.render(renderPass)

    // Verify the output matches the golden image
    let image = try texture.cgImage
    #expect(try image.isEqualToGoldenImage(named: "FlatShaderRotated"))
}

@Test
@MainActor
func testFlatShaderWithVertexColors() throws {
    // Define vertex structure with colors
    struct VertexWithColor {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
        var textureCoordinate: SIMD2<Float>
        var color: SIMD4<Float>
    }

    // Create a quad with different colors at each vertex (gradient effect)
    let vertices: [VertexWithColor] = [
        // Triangle 1
        VertexWithColor(
            position: [-0.5, -0.5, 0],
            normal: [0, 0, 1],
            textureCoordinate: [0, 0],
            color: [1, 0, 0, 1]  // Red
        ),
        VertexWithColor(
            position: [0.5, -0.5, 0],
            normal: [0, 0, 1],
            textureCoordinate: [1, 0],
            color: [0, 1, 0, 1]  // Green
        ),
        VertexWithColor(
            position: [0.5, 0.5, 0],
            normal: [0, 0, 1],
            textureCoordinate: [1, 1],
            color: [0, 0, 1, 1]  // Blue
        ),
        // Triangle 2
        VertexWithColor(
            position: [-0.5, -0.5, 0],
            normal: [0, 0, 1],
            textureCoordinate: [0, 0],
            color: [1, 0, 0, 1]  // Red
        ),
        VertexWithColor(
            position: [0.5, 0.5, 0],
            normal: [0, 0, 1],
            textureCoordinate: [1, 1],
            color: [0, 0, 1, 1]  // Blue
        ),
        VertexWithColor(
            position: [-0.5, 0.5, 0],
            normal: [0, 0, 1],
            textureCoordinate: [0, 1],
            color: [1, 1, 0, 1]  // Yellow
        ),
    ]

    // Create an identity matrix
    let modelViewProjection = matrix_identity_float4x4

    // Use a white color source so vertex colors show through
    let colorSource = ColorSource.color([1.0, 1.0, 1.0])

    // Create vertex descriptor including the color attribute
    let vertexDescriptor = MTLVertexDescriptor()
    // position - attribute 0
    vertexDescriptor.attributes[0].format = .float3
    vertexDescriptor.attributes[0].offset = 0
    vertexDescriptor.attributes[0].bufferIndex = 0
    // normal - attribute 1
    vertexDescriptor.attributes[1].format = .float3
    vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
    vertexDescriptor.attributes[1].bufferIndex = 0
    // textureCoordinate - attribute 2
    vertexDescriptor.attributes[2].format = .float2
    vertexDescriptor.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride * 2
    vertexDescriptor.attributes[2].bufferIndex = 0
    // color - attribute 3 (NEW!)
    vertexDescriptor.attributes[3].format = .float4
    vertexDescriptor.attributes[3].offset = MemoryLayout<SIMD3<Float>>.stride * 2 + MemoryLayout<SIMD2<Float>>.stride
    vertexDescriptor.attributes[3].bufferIndex = 0
    // layout
    vertexDescriptor.layouts[0].stride = MemoryLayout<VertexWithColor>.stride
    vertexDescriptor.layouts[0].stepFunction = .perVertex

    // Create the render pass with FlatShader - NOTE: useVertexColors: true
    let renderPass = try RenderPass {
        try FlatShader(
            modelViewProjection: modelViewProjection,
            textureSpecifier: colorSource,
            useVertexColors: true  // Enable vertex colors!
        ) {
            Draw { encoder in
                encoder.setVertexBytes(vertices, length: MemoryLayout<VertexWithColor>.stride * vertices.count, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
            }
        }
        .vertexDescriptor(vertexDescriptor)
    }

    // Render offscreen
    let offscreenRenderer = try OffscreenRenderer(size: CGSize(width: 400, height: 400))
    let texture = try offscreenRenderer.render(renderPass)

    // Verify the output matches the golden image
    let image = try texture.cgImage
    #expect(try image.isEqualToGoldenImage(named: "FlatShaderVertexColors"))
}
