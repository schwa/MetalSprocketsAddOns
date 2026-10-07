import Metal
import MetalSprockets
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import MetalSupport

public extension Light {
    init(type: LightType, color: SIMD3<Float> = [1, 1, 1], intensity: Float = 1.0) {
        self.init(type: type, color: color, intensity: intensity, range: .infinity)
    }
}

public struct Lighting {
    // Shared by copies, so the non-mutating setters below can swap buffers.
    private final class Storage {
        var lights: MTLBuffer
        var lightPositions: MTLBuffer

        init(lights: MTLBuffer, lightPositions: MTLBuffer) {
            self.lights = lights
            self.lightPositions = lightPositions
        }
    }

    public var ambientLightColor: simd_float3
    public var count: Int
    private var storage: Storage

    public var lights: MTLBuffer {
        get { storage.lights }
        set { storage.lights = newValue }
    }

    public var lightPositions: MTLBuffer {
        get { storage.lightPositions }
        set { storage.lightPositions = newValue }
    }
}

public extension Lighting {
    init(ambientLightColor: SIMD3<Float>, lights: [(SIMD3<Float>, Light)], capacity: Int? = nil) throws {
        assert(!lights.isEmpty)
        let device = _MTLCreateSystemDefaultDevice()
        self.ambientLightColor = ambientLightColor
        self.count = lights.count
        self.storage = Storage(
            lights: try device.makeBuffer(unsafeBytesOf: lights.map(\.1)),
            lightPositions: try device.makeBuffer(unsafeBytesOf: lights.map(\.0))
        )
    }
}

extension Lighting: ArgumentBufferRepresentable {
    public var argumentBufferResources: [any MTLResource] {
        [lights, lightPositions]
    }

    public func toArgumentBuffer() throws -> LightingArgumentBuffer {
        LightingArgumentBuffer(
            ambientLightColor: ambientLightColor,
            lightCount: Int32(count),
            lights: lights.gpuAddressAsUnsafeMutablePointer(type: Light.self).orFatalError("Failed to get GPU address for lights buffer"),
            lightPositions: lightPositions.gpuAddressAsUnsafeMutablePointer(type: SIMD3<Float>.self).orFatalError("Failed to get GPU address for lightPositions buffer")
        )
    }
}

// Setters write into a fresh copy of the buffer: frames still in flight keep reading the buffer
// they bound, which their submission retains until it completes.
public extension Lighting {
    /// Update the position of a light at the given index.
    func setLightPosition(_ position: SIMD3<Float>, at index: Int) {
        let buffer = Self.copy(storage.lightPositions)
        buffer.contents()
            .advanced(by: index * MemoryLayout<SIMD3<Float>>.stride)
            .assumingMemoryBound(to: SIMD3<Float>.self)
            .pointee = position
        storage.lightPositions = buffer
    }

    /// Update the light value at the given index.
    func setLight(_ light: Light, at index: Int) {
        let buffer = Self.copy(storage.lights)
        buffer.contents()
            .advanced(by: index * MemoryLayout<Light>.stride)
            .assumingMemoryBound(to: Light.self)
            .pointee = light
        storage.lights = buffer
    }

    private static func copy(_ buffer: MTLBuffer) -> MTLBuffer {
        let copy = buffer.device.makeBuffer(bytes: buffer.contents(), length: buffer.length, options: buffer.resourceOptions)
            .orFatalError("Failed to copy lighting buffer")
        copy.label = buffer.label
        return copy
    }
}

public extension Element {
    func lighting(_ lighting: Lighting) throws -> some Element {
        try argumentBuffer("lighting", value: lighting)
    }
}
