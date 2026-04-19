import CoreGraphics
import GeometryLite3D
import Metal
import MetalKit
import MetalSprockets
@testable import MetalSprocketsAddOns
import MetalSprocketsSupport
import MetalSupport
import ModelIO
import simd

// MARK: - Standard render size

/// Default offscreen render size for golden-image tests.
/// Smaller than UI sizes to keep golden PNGs lightweight.
let defaultRenderSize = CGSize(width: 256, height: 256)

// MARK: - Camera helpers

/// Standard perspective projection used by most golden tests.
func perspectiveProjection(aspect: Float = 1.0) -> simd_float4x4 {
    PerspectiveProjection(verticalAngleOfView: .degrees(60), depthMode: .standard(zClip: 0.1...100))
        .projectionMatrix(aspectRatio: aspect)
}

/// A camera looking at the origin from `(0, 0, distance)` (right-handed, +Y up).
func lookAtOriginCameraMatrix(distance: Float = 3.0) -> simd_float4x4 {
    float4x4(translation: SIMD3<Float>(0, 0, distance))
}

// MARK: - Texture helpers

/// Make a small RGBA8 checkerboard texture useful for sampling tests.
func makeCheckerboardTexture(device: MTLDevice, size: Int = 8) throws -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm,
        width: size,
        height: size,
        mipmapped: false
    )
    descriptor.usage = [.shaderRead]
    descriptor.storageMode = .shared
    let texture = try device.makeTexture(descriptor: descriptor)
        .orThrow(.resourceCreationFailure("Failed to create checkerboard texture"))
    var pixels = [UInt8]()
    pixels.reserveCapacity(size * size * 4)
    for y in 0..<size {
        for x in 0..<size {
            if (x + y).isMultiple(of: 2) {
                pixels.append(contentsOf: [255, 255, 255, 255])
            } else {
                pixels.append(contentsOf: [16, 16, 16, 255])
            }
        }
    }
    let region = MTLRegionMake2D(0, 0, size, size)
    texture.replace(region: region, mipmapLevel: 0, withBytes: pixels, bytesPerRow: size * 4)
    return texture
}

/// Make a solid-color RGBA8 texture.
func makeSolidColorTexture(device: MTLDevice, size: Int = 4, color: SIMD4<UInt8>) throws -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm,
        width: size,
        height: size,
        mipmapped: false
    )
    descriptor.usage = [.shaderRead]
    descriptor.storageMode = .shared
    let texture = try device.makeTexture(descriptor: descriptor)
        .orThrow(.resourceCreationFailure("Failed to create solid color texture"))
    let pixels = (0..<(size * size * 4)).map { idx in
        color[idx % 4]
    }
    let region = MTLRegionMake2D(0, 0, size, size)
    texture.replace(region: region, mipmapLevel: 0, withBytes: pixels, bytesPerRow: size * 4)
    return texture
}

// MARK: - Mesh helpers

/// Make a box MTKMesh with a full vertex layout (position, normal, texcoord, tangent, bitangent),
/// suitable for shaders like the debug/Blinn-Phong shaders that require tangent space attributes.
func makeBoxMeshWithTangents(extent: SIMD3<Float> = [1, 1, 1]) throws -> MTKMesh {
    let device = _MTLCreateSystemDefaultDevice()
    let allocator = MTKMeshBufferAllocator(device: device)
    let mdlMesh = MDLMesh(
        boxWithExtent: extent,
        segments: [1, 1, 1],
        inwardNormals: false,
        geometryType: .triangles,
        allocator: allocator
    )
    mdlMesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.0)
    mdlMesh.addTangentBasis(
        forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
        tangentAttributeNamed: MDLVertexAttributeTangent,
        bitangentAttributeNamed: MDLVertexAttributeBitangent
    )
    return try MTKMesh(mesh: mdlMesh, device: device)
}

/// Make a sphere MTKMesh with a full vertex layout (position, normal, texcoord, tangent, bitangent).
func makeSphereMeshWithTangents(extent: SIMD3<Float> = [1, 1, 1], segments: SIMD2<UInt32> = [32, 32]) throws -> MTKMesh {
    let device = _MTLCreateSystemDefaultDevice()
    let allocator = MTKMeshBufferAllocator(device: device)
    let mdlMesh = MDLMesh(
        sphereWithExtent: extent,
        segments: segments,
        inwardNormals: false,
        geometryType: .triangles,
        allocator: allocator
    )
    mdlMesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.0)
    mdlMesh.addTangentBasis(
        forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
        tangentAttributeNamed: MDLVertexAttributeTangent,
        bitangentAttributeNamed: MDLVertexAttributeBitangent
    )
    return try MTKMesh(mesh: mdlMesh, device: device)
}

/// Make a simple gradient cube texture for skybox tests.
func makeGradientCubeTexture(device: MTLDevice, size: Int = 8) throws -> MTLTexture {
    let descriptor = MTLTextureDescriptor()
    descriptor.textureType = .typeCube
    descriptor.pixelFormat = .rgba8Unorm
    descriptor.width = size
    descriptor.height = size
    descriptor.usage = [.shaderRead]
    descriptor.storageMode = .shared
    let texture = try device.makeTexture(descriptor: descriptor)
        .orThrow(.resourceCreationFailure("Failed to create cube texture"))
    // Fill each face with a distinct solid color.
    let faceColors: [SIMD4<UInt8>] = [
        [255, 64, 64, 255],   // +X red
        [64, 255, 64, 255],   // -X green (will read as opposite face)
        [64, 64, 255, 255],   // +Y blue
        [255, 255, 64, 255],  // -Y yellow
        [255, 64, 255, 255],  // +Z magenta
        [64, 255, 255, 255]   // -Z cyan
    ]
    for face in 0..<6 {
        let color = faceColors[face]
        var pixels = [UInt8]()
        pixels.reserveCapacity(size * size * 4)
        for _ in 0..<(size * size) {
            pixels.append(contentsOf: [color.x, color.y, color.z, color.w])
        }
        let region = MTLRegionMake2D(0, 0, size, size)
        texture.replace(region: region, mipmapLevel: 0, slice: face, withBytes: pixels, bytesPerRow: size * 4, bytesPerImage: size * size * 4)
    }
    return texture
}
