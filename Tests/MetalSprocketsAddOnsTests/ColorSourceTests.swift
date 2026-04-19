// Direct unit tests for ColorSource accessors and argument-buffer conversion.

import Metal
@testable import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import MetalSupport
import simd
import Testing

// MARK: - Convenience initializers

@Test
@MainActor
func testColorSource_texture2DConvenience_omitsSampler() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let texture = try makeCheckerboardTexture(device: device, size: 4)
    let source = ColorSource.texture2D(texture)

    #expect(source.texture2D === texture)
    #expect(source.textureCube == nil)
    #expect(source.depth2D == nil)
}

@Test
func testColorSource_colorScalarConvenience_broadcastsToVec3() {
    let source = ColorSource.color(0.5)
    if case let .color(value) = source {
        #expect(value == SIMD3<Float>(0.5, 0.5, 0.5))
    } else {
        Issue.record("expected .color case")
    }
}

// MARK: - Accessors

@Test
@MainActor
func testColorSource_textureCubeAccessor() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let cube = try makeGradientCubeTexture(device: device, size: 4)
    let source = ColorSource.textureCube(cube, nil, 0)

    #expect(source.textureCube === cube)
    #expect(source.texture2D == nil)
    #expect(source.depth2D == nil)
}

@Test
@MainActor
func testColorSource_depth2DAccessor() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .depth32Float,
        width: 8,
        height: 8,
        mipmapped: false
    )
    descriptor.usage = [.shaderRead]
    descriptor.storageMode = .private
    let depth = try device.makeTexture(descriptor: descriptor)
        .orThrow(.resourceCreationFailure("Failed to create depth texture"))

    let source = ColorSource.depth2D(depth, nil)
    #expect(source.depth2D === depth)
    #expect(source.texture2D == nil)
    #expect(source.textureCube == nil)
}

@Test
func testColorSource_colorAccessorsReturnNil_forNonTextureCases() {
    let source = ColorSource.color([0.1, 0.2, 0.3])
    #expect(source.texture2D == nil)
    #expect(source.textureCube == nil)
    #expect(source.depth2D == nil)
}

// MARK: - toArgumentBuffer

@Test
@MainActor
func testColorSource_toArgumentBuffer_color() {
    let argBuffer = ColorSource.color([0.25, 0.5, 0.75]).toArgumentBuffer()
    #expect(argBuffer.source == .color)
    #expect(argBuffer.color == SIMD3<Float>(0.25, 0.5, 0.75))
}

@Test
@MainActor
func testColorSource_toArgumentBuffer_texture2D() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let texture = try makeCheckerboardTexture(device: device, size: 4)
    let argBuffer = ColorSource.texture2D(texture).toArgumentBuffer()
    #expect(argBuffer.source == .texture2D)
}

@Test
@MainActor
func testColorSource_toArgumentBuffer_textureCubeWithSlice() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let cube = try makeGradientCubeTexture(device: device, size: 4)
    let argBuffer = ColorSource.textureCube(cube, nil, 3).toArgumentBuffer()
    #expect(argBuffer.source == .textureCube)
    #expect(argBuffer.slice == 3)
}

@Test
@MainActor
func testColorSource_toArgumentBuffer_depth2D() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .depth32Float,
        width: 8,
        height: 8,
        mipmapped: false
    )
    descriptor.usage = [.shaderRead]
    descriptor.storageMode = .private
    let depth = try device.makeTexture(descriptor: descriptor)
        .orThrow(.resourceCreationFailure("Failed to create depth texture"))

    let argBuffer = ColorSource.depth2D(depth, nil).toArgumentBuffer()
    #expect(argBuffer.source == .depth2D)
}

@Test
@MainActor
func testColorSource_toArgumentBuffer_withSampler() throws {
    let device = _MTLCreateSystemDefaultDevice()
    let texture = try makeCheckerboardTexture(device: device, size: 4)
    let samplerDesc = MTLSamplerDescriptor()
    samplerDesc.minFilter = .linear
    samplerDesc.magFilter = .linear
    let sampler = device.makeSamplerState(descriptor: samplerDesc)!

    let argBuffer = ColorSource.texture2D(texture, sampler).toArgumentBuffer()
    #expect(argBuffer.source == .texture2D)
}
