import Metal
import MetalSprockets
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport

public struct BlinnPhongMaterial {
    public var ambient: ColorSource
    public var diffuse: ColorSource
    public var specular: ColorSource
    public var shininess: Float

    public init(ambient: ColorSource, diffuse: ColorSource, specular: ColorSource, shininess: Float) {
        self.ambient = ambient
        self.diffuse = diffuse
        self.specular = specular
        self.shininess = shininess
    }
}

public extension BlinnPhongMaterial {
    func toArgumentBuffer() throws -> BlinnPhongMaterialArgumentBuffer {
        var result = BlinnPhongMaterialArgumentBuffer()
        result.ambient = ambient.toArgumentBuffer()
        result.diffuse = diffuse.toArgumentBuffer()
        result.specular = specular.toArgumentBuffer()
        result.shininess = shininess
        return result
    }
}

public extension Element {
    func blinnPhongMaterial(_ material: BlinnPhongMaterial) throws -> some Element {
        self
            .parameter("material", value: try material.toArgumentBuffer())
            .useResource(material.ambient.texture2D, usage: .read, stages: .fragment)
            .useResource(material.diffuse.texture2D, usage: .read, stages: .fragment)
            .useResource(material.specular.texture2D, usage: .read, stages: .fragment)
    }

    func blinnPhongMatrices(projectionMatrix: simd_float4x4, viewMatrix: simd_float4x4, modelMatrix: simd_float4x4, cameraMatrix: simd_float4x4) -> some Element {
        // Pre-compute matrix products on CPU to avoid per-vertex computation
        let modelViewMatrix = viewMatrix * modelMatrix
        let modelViewProjectionMatrix = projectionMatrix * modelViewMatrix

        return self
            .parameter("modelViewMatrix", functionType: .vertex, value: modelViewMatrix)
            .parameter("modelViewProjectionMatrix", functionType: .vertex, value: modelViewProjectionMatrix)
            .parameter("modelMatrix", functionType: .vertex, value: modelMatrix)
            .parameter("cameraMatrix", functionType: .fragment, value: cameraMatrix)
    }
}
