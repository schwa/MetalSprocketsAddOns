import GeometryLite3D
import MetalSprockets
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import simd
import SwiftUI

public struct GridShader: Element {
    @MSState
    private var vertexShader = ShaderLibrary.module.namespaced("GridShader").requiredFunction(named: "vertex_main", type: VertexShader.self)

    @MSState
    private var fragmentShader = ShaderLibrary.module.namespaced("GridShader").requiredFunction(named: "fragment_main", type: FragmentShader.self)

    var projectionMatrix: simd_float4x4
    var cameraMatrix: simd_float4x4

    public init(projectionMatrix: simd_float4x4, cameraMatrix: simd_float4x4) {
        self.projectionMatrix = projectionMatrix
        self.cameraMatrix = cameraMatrix
    }

    public var body: some Element {
        get throws {
            try RenderPipeline(vertexShader: vertexShader, fragmentShader: fragmentShader) {
                let modelMatrix = float4x4(xRotation: .degrees(90))
                let modelViewProjectionMatrix = projectionMatrix * cameraMatrix.inverse * modelMatrix
                Draw { encoder in
                    let positions: [Packed3<Float>] = [
                        [-1, 1, 0], [-1, -1, 0], [1, 1, 0], [1, -1, 0]
                    ]
                    .map { $0 * 2_000 }
                    let textureCoordinates: [SIMD2<Float>] = [
                        [0, 1], [0, 0], [1, 1], [1, 0]
                    ]
                    //                    encoder.setTriangleFillMode(.lines)
                    encoder.setVertexUnsafeBytes(of: positions, index: 0)
                    encoder.setVertexUnsafeBytes(of: textureCoordinates, index: 1)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: positions.count)
                }
                .parameter("modelViewProjectionMatrix", value: modelViewProjectionMatrix)
                .parameter("gridColor", value: SIMD4<Float>(1, 1, 1, 1))
                .parameter("backgroundColor", value: SIMD4<Float>(0.1, 0.1, 0.1, 1))
                .parameter("gridScale", value: SIMD2<Float>(0.0005, 0.0005))
            }
            .vertexDescriptor(try vertexShader.inferredVertexDescriptor())
        }
    }
}
