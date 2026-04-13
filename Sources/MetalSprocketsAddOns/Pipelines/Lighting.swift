import Metal
import MetalSprockets
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport

public extension Light {
    init(type: LightType, color: SIMD3<Float> = [1, 1, 1], intensity: Float = 1.0) {
        self.init(type: type, color: color, intensity: intensity, range: .infinity)
    }
}

public struct Lighting {
    public var ambientLightColor: simd_float3
    public var count: Int
    public var lights: MTLBuffer
    public var lightPositions: MTLBuffer
}

public extension Lighting {
    init(ambientLightColor: SIMD3<Float>, lights: [(SIMD3<Float>, Light)], capacity: Int? = nil) throws {
        assert(!lights.isEmpty)
        let device = _MTLCreateSystemDefaultDevice()
        self.ambientLightColor = ambientLightColor
        self.count = lights.count
        self.lights = try device.makeBuffer(unsafeBytesOf: lights.map(\.1))
        self.lightPositions = try device.makeBuffer(unsafeBytesOf: lights.map(\.0))
    }
}

public extension Lighting {
    func toArgumentBuffer() throws -> LightingArgumentBuffer {
        LightingArgumentBuffer(
            ambientLightColor: ambientLightColor,
            lightCount: Int32(count),
            lights: lights.gpuAddressAsUnsafeMutablePointer(type: Light.self).orFatalError("Failed to get GPU address for lights buffer"),
            lightPositions: lightPositions.gpuAddressAsUnsafeMutablePointer(type: SIMD3<Float>.self).orFatalError("Failed to get GPU address for lightPositions buffer")
        )
    }
}

public extension Element {
    func lighting(_ lighting: Lighting) throws -> some Element {
        self
            .parameter("lighting", value: try lighting.toArgumentBuffer())
            .useResource(lighting.lights, usage: .read, stages: .fragment)
            .useResource(lighting.lightPositions, usage: .read, stages: .fragment)
    }
}
