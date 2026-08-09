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

extension BlinnPhongMaterial: ArgumentBufferRepresentable {
    public var argumentBufferResources: [any MTLResource] {
        ambient.argumentBufferResources + diffuse.argumentBufferResources + specular.argumentBufferResources
    }

    public func toArgumentBuffer() throws -> BlinnPhongMaterialArgumentBuffer {
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
        try argumentBuffer("material", value: material)
    }

    /// Binds the standard Blinn-Phong matrix parameters, derived from shared ``Transforms``.
    func blinnPhongMatrices(_ transforms: Transforms) -> some Element {
        // Matrix products are derived once on the CPU to avoid per-vertex computation.
        self
            .parameter("modelViewMatrix", functionType: .vertex, value: transforms.modelViewMatrix)
            .parameter("modelViewProjectionMatrix", functionType: .vertex, value: transforms.modelViewProjectionMatrix)
            .parameter("modelMatrix", functionType: .vertex, value: transforms.modelMatrix)
            .parameter("cameraMatrix", functionType: .fragment, value: transforms.cameraMatrix)
    }

    func blinnPhongMatrices(projectionMatrix: simd_float4x4, viewMatrix: simd_float4x4, modelMatrix: simd_float4x4, cameraMatrix: simd_float4x4) -> some Element {
        // `viewMatrix` and `cameraMatrix` are passed separately by legacy callers; the shared
        // type derives one from the other, so the camera matrix wins and the view matrix is
        // recomputed from it.
        blinnPhongMatrices(Transforms(projectionMatrix: projectionMatrix, cameraMatrix: cameraMatrix, modelMatrix: modelMatrix))
    }
}
