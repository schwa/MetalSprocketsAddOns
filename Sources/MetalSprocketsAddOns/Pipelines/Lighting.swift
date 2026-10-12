import Metal
import MetalSprockets
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import MetalSupport

public extension Light {
    init(type: LightType, color: SIMD3<Float> = [1, 1, 1], intensity: Float = 1.0) {
        self.init(type: type, color: color, intensity: intensity, range: .infinity, innerConeAngle: .pi / 8, outerConeAngle: .pi / 6)
    }

    /// A spot light. Cone angles are half-angles in radians.
    static func spot(color: SIMD3<Float> = [1, 1, 1], intensity: Float = 1.0, range: Float = .infinity, innerConeAngle: Float = .pi / 8, outerConeAngle: Float = .pi / 6) -> Light {
        Light(type: .spot, color: color, intensity: intensity, range: range, innerConeAngle: innerConeAngle, outerConeAngle: outerConeAngle)
    }
}

public struct Lighting {
    // Shared by copies, so the non-mutating setters below can swap buffers.
    private final class Storage {
        var lights: MTLBuffer
        var lightPositions: MTLBuffer
        var lightDirections: MTLBuffer

        init(lights: MTLBuffer, lightPositions: MTLBuffer, lightDirections: MTLBuffer) {
            self.lights = lights
            self.lightPositions = lightPositions
            self.lightDirections = lightDirections
        }
    }

    public static let defaultLightDirection: SIMD3<Float> = [0, 0, -1]

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

    public var lightDirections: MTLBuffer {
        get { storage.lightDirections }
        set { storage.lightDirections = newValue }
    }
}

public extension Lighting {
    /// Lights with a position only. Directional and spot lights get `defaultLightDirection`.
    init(ambientLightColor: SIMD3<Float>, lights: [(SIMD3<Float>, Light)], capacity: Int? = nil) throws {
        try self.init(ambientLightColor: ambientLightColor, orientedLights: lights.map { (position: $0.0, direction: Self.defaultLightDirection, light: $0.1) })
    }

    /// `direction` is the way the light points. Point lights ignore it; directional lights ignore `position`.
    init(ambientLightColor: SIMD3<Float>, orientedLights lights: [(position: SIMD3<Float>, direction: SIMD3<Float>, light: Light)]) throws {
        assert(!lights.isEmpty)
        let device = _MTLCreateSystemDefaultDevice()
        self.ambientLightColor = ambientLightColor
        self.count = lights.count
        self.storage = Storage(
            lights: try device.makeBuffer(unsafeBytesOf: lights.map(\.light)),
            lightPositions: try device.makeBuffer(unsafeBytesOf: lights.map(\.position)),
            lightDirections: try device.makeBuffer(unsafeBytesOf: lights.map { simd_normalize($0.direction) })
        )
    }
}

extension Lighting: ArgumentBufferRepresentable {
    public var argumentBufferResources: [any MTLResource] {
        [lights, lightPositions, lightDirections]
    }

    public func toArgumentBuffer() throws -> LightingArgumentBuffer {
        LightingArgumentBuffer(
            ambientLightColor: ambientLightColor,
            lightCount: Int32(count),
            lights: lights.gpuAddressAsUnsafeMutablePointer(type: Light.self).orFatalError("Failed to get GPU address for lights buffer"),
            lightPositions: lightPositions.gpuAddressAsUnsafeMutablePointer(type: SIMD3<Float>.self).orFatalError("Failed to get GPU address for lightPositions buffer"),
            lightDirections: lightDirections.gpuAddressAsUnsafeMutablePointer(type: SIMD3<Float>.self).orFatalError("Failed to get GPU address for lightDirections buffer")
        )
    }
}

// Setters write into a fresh copy of the buffer: frames still in flight keep reading the buffer
// they bound, which their submission retains until it completes.
public extension Lighting {
    /// Update the position of a light at the given index.
    func setLightPosition(_ position: SIMD3<Float>, at index: Int) {
        storage.lightPositions = Self.copy(storage.lightPositions, replacing: position, at: index)
    }

    /// Update the direction of a light at the given index.
    func setLightDirection(_ direction: SIMD3<Float>, at index: Int) {
        storage.lightDirections = Self.copy(storage.lightDirections, replacing: simd_normalize(direction), at: index)
    }

    /// Update the light value at the given index.
    func setLight(_ light: Light, at index: Int) {
        storage.lights = Self.copy(storage.lights, replacing: light, at: index)
    }

    private static func copy<Value>(_ buffer: MTLBuffer, replacing value: Value, at index: Int) -> MTLBuffer {
        let copy = buffer.device.makeBuffer(bytes: buffer.contents(), length: buffer.length, options: buffer.resourceOptions)
            .orFatalError("Failed to copy lighting buffer")
        copy.label = buffer.label
        copy.contents()
            .advanced(by: index * MemoryLayout<Value>.stride)
            .assumingMemoryBound(to: Value.self)
            .pointee = value
        return copy
    }
}

public extension Element {
    func lighting(_ lighting: Lighting) throws -> some Element {
        try argumentBuffer("lighting", value: lighting)
    }
}
