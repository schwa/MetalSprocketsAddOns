import CoreGraphics
import MetalSprockets
import simd

public struct LambertianShader <Content>: Element where Content: Element {
    var transforms: Transforms
    var color: SIMD3<Float>

    @MSState
    private var vertexShader = ShaderLibrary.module.namespaced("LambertianShader").requiredFunction(named: "vertex_main", type: VertexShader.self)

    @MSState
    private var fragmentShader = ShaderLibrary.module.namespaced("LambertianShader").requiredFunction(named: "fragment_main", type: FragmentShader.self)

    var lightDirection: SIMD3<Float>
    var content: Content

    public init(transforms: Transforms, color: SIMD3<Float>, lightDirection: SIMD3<Float>, content: () -> Content) {
        self.transforms = transforms
        self.color = color
        self.lightDirection = lightDirection
        self.content = content()
    }

    public init(projectionMatrix: float4x4, cameraMatrix: float4x4, modelMatrix: float4x4, color: SIMD3<Float>, lightDirection: SIMD3<Float>, content: () -> Content) {
        self.init(
            transforms: Transforms(projectionMatrix: projectionMatrix, cameraMatrix: cameraMatrix, modelMatrix: modelMatrix),
            color: color,
            lightDirection: lightDirection,
            content: content
        )
    }

    public var body: some Element {
        get throws {
            // Matrix products are derived once on the CPU to avoid per-vertex computation.
            try RenderPipeline(label: "Lambertian", vertexShader: vertexShader, fragmentShader: fragmentShader) {
                content
                    .parameter("modelViewProjectionMatrix", value: transforms.modelViewProjectionMatrix)
                    .parameter("modelMatrix", value: transforms.modelMatrix)
                    .parameter("normalMatrix", value: transforms.normalMatrix)
                    .parameter("color", value: color)
                    .parameter("cameraPosition", value: transforms.cameraPosition)
                    .parameter("lightDirection", value: lightDirection)
            }
        }
    }
}

public struct LambertianShaderInstanced <Content>: Element where Content: Element {
    var viewTransforms: ViewTransforms
    var colors: [SIMD3<Float>]
    var modelMatrices: [simd_float4x4]

    @MSState
    private var vertexShader = ShaderLibrary.module.namespaced("LambertianShader").requiredFunction(named: "vertex_instanced", type: VertexShader.self)

    @MSState
    private var fragmentShader = ShaderLibrary.module.namespaced("LambertianShader").requiredFunction(named: "fragment_main", type: FragmentShader.self)

    var lightDirection: SIMD3<Float>
    var content: Content

    public init(viewTransforms: ViewTransforms, colors: [SIMD3<Float>], modelMatrices: [simd_float4x4], lightDirection: SIMD3<Float>, @ElementBuilder content: () -> Content) {
        self.viewTransforms = viewTransforms
        self.colors = colors
        self.modelMatrices = modelMatrices
        self.lightDirection = lightDirection
        self.content = content()
    }

    public init(projectionMatrix: float4x4, cameraMatrix: float4x4, colors: [SIMD3<Float>], modelMatrices: [simd_float4x4], lightDirection: SIMD3<Float>, @ElementBuilder content: () -> Content) {
        self.init(
            viewTransforms: ViewTransforms(projectionMatrix: projectionMatrix, cameraMatrix: cameraMatrix),
            colors: colors,
            modelMatrices: modelMatrices,
            lightDirection: lightDirection,
            content: content
        )
    }

    public var body: some Element {
        get throws {
            // Per-instance matrices are derived once on the CPU to avoid per-vertex computation.
            let instanceTransforms = modelMatrices.map(viewTransforms.transforms(modelMatrix:))
            let modelViewProjectionMatrices = instanceTransforms.map(\.modelViewProjectionMatrix)
            let normalMatrices = instanceTransforms.map(\.normalMatrix)

            return try RenderPipeline(label: "Lambertian Instanced", vertexShader: vertexShader, fragmentShader: fragmentShader) {
                content
                    .parameter("modelViewProjectionMatrices", values: modelViewProjectionMatrices)
                    .parameter("modelMatrices", values: modelMatrices)
                    .parameter("normalMatrices", values: normalMatrices)
                    .parameter("colors", values: colors)
                    .parameter("lightDirection", value: lightDirection)
                    .parameter("cameraPosition", value: viewTransforms.cameraPosition)
            }
        }
    }
}
