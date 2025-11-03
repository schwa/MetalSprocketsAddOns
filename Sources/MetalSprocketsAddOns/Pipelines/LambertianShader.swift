import CoreGraphics
import MetalSprockets
import simd

public struct LambertianShader <Content>: Element where Content: Element {
    var projectionMatrix: float4x4
    var cameraMatrix: float4x4
    var modelMatrix: float4x4
    var color: SIMD3<Float>

    @MSState
    private var vertexShader = ShaderLibrary.module.namespaced("LambertianShader").requiredFunction(named: "vertex_main", type: VertexShader.self)

    @MSState
    private var fragmentShader = ShaderLibrary.module.namespaced("LambertianShader").requiredFunction(named: "fragment_main", type: FragmentShader.self)

    var lightDirection: SIMD3<Float>
    var content: Content

    public init(projectionMatrix: float4x4, cameraMatrix: float4x4, modelMatrix: float4x4, color: SIMD3<Float>, lightDirection: SIMD3<Float>, content: () -> Content) {
        self.projectionMatrix = projectionMatrix
        self.cameraMatrix = cameraMatrix
        self.modelMatrix = modelMatrix
        self.color = color
        self.lightDirection = lightDirection
        self.content = content()
    }

    public var body: some Element {
        get throws {
            // Pre-compute matrix products on CPU to avoid per-vertex computation
            let viewMatrix = cameraMatrix.inverse
            let modelViewProjectionMatrix = projectionMatrix * viewMatrix * modelMatrix

            // Pre-compute normal matrix on CPU (upper-left 3x3 of model matrix)
            let normalMatrix = float3x3(
                modelMatrix.columns.0.xyz,
                modelMatrix.columns.1.xyz,
                modelMatrix.columns.2.xyz
            )

            return try RenderPipeline(vertexShader: vertexShader, fragmentShader: fragmentShader) {
                content
                    .parameter("modelViewProjectionMatrix", value: modelViewProjectionMatrix)
                    .parameter("modelMatrix", value: modelMatrix)
                    .parameter("normalMatrix", value: normalMatrix)
                    .parameter("color", value: color)
                    .parameter("cameraPosition", value: cameraMatrix.translation)
                    .parameter("lightDirection", value: lightDirection)
            }
        }
    }
}

public struct LambertianShaderInstanced <Content>: Element where Content: Element {
    var projectionMatrix: float4x4
    var cameraMatrix: float4x4
    var colors: [SIMD3<Float>]
    var modelMatrices: [simd_float4x4]

    @MSState
    private var vertexShader = ShaderLibrary.module.namespaced("LambertianShader").requiredFunction(named: "vertex_instanced", type: VertexShader.self)

    @MSState
    private var fragmentShader = ShaderLibrary.module.namespaced("LambertianShader").requiredFunction(named: "fragment_main", type: FragmentShader.self)

    var lightDirection: SIMD3<Float>
    var content: Content

    public init(projectionMatrix: float4x4, cameraMatrix: float4x4, colors: [SIMD3<Float>], modelMatrices: [simd_float4x4], lightDirection: SIMD3<Float>, @ElementBuilder content: () -> Content) {
        self.projectionMatrix = projectionMatrix
        self.cameraMatrix = cameraMatrix
        self.colors = colors
        self.modelMatrices = modelMatrices
        self.lightDirection = lightDirection
        self.content = content()
    }

    public var body: some Element {
        get throws {
            // Pre-compute all per-instance matrices on CPU to avoid per-vertex computation
            let viewMatrix = cameraMatrix.inverse
            let viewProjectionMatrix = projectionMatrix * viewMatrix

            // Pre-compute MVP matrices for all instances
            let modelViewProjectionMatrices = modelMatrices.map { modelMatrix in
                viewProjectionMatrix * modelMatrix
            }

            // Pre-compute normal matrices for all instances (upper-left 3x3 of each model matrix)
            let normalMatrices = modelMatrices.map { modelMatrix in
                float3x3(
                    modelMatrix.columns.0.xyz,
                    modelMatrix.columns.1.xyz,
                    modelMatrix.columns.2.xyz
                )
            }

            return try RenderPipeline(vertexShader: vertexShader, fragmentShader: fragmentShader) {
                content
                    .parameter("modelViewProjectionMatrices", values: modelViewProjectionMatrices)
                    .parameter("modelMatrices", values: modelMatrices)
                    .parameter("normalMatrices", values: normalMatrices)
                    .parameter("colors", values: colors)
                    .parameter("lightDirection", value: lightDirection)
                    .parameter("cameraPosition", value: cameraMatrix.translation)
            }
        }
    }
}
