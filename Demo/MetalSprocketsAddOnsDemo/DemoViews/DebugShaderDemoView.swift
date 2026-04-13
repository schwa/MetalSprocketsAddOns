import DemoKit
import GeometryLite3D
import Interaction3D
import MetalKit
import MetalSprockets
import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsSupport
import MetalSprocketsUI
import simd
import SwiftUI

struct DebugShaderDemoView: DemoView {
    static let metadata = DemoMetadata(
        name: "Debug Shader",
        systemImage: "eye.trianglebadge.exclamationmark",
        description: "Switchable debug visualization modes: normals, tangents, UVs, depth, wireframe, and more",
        group: "Rendering"
    )

    @State private var cameraRotation = simd_quatf(angle: -.pi / 6, axis: [1, 0, 0])
    @State private var cameraDistance: Float = 6
    @State private var cameraTarget: SIMD3<Float> = [0, 1, 0]

    @State private var debugMode: DebugShadersMode = .normal
    @State private var showInspector = true

    let teapot = MTKMesh.teapot(options: [.generateTangentBasis, .generateTextureCoordinatesIfMissing, .useSimpleTextureCoordinates])

    private var cameraMatrix: simd_float4x4 {
        let rotation = float4x4(cameraRotation)
        let translation = float4x4.translation(cameraTarget.x, cameraTarget.y, cameraTarget.z)
        let distance = float4x4.translation(0, 0, cameraDistance)
        return translation * rotation * distance
    }

    var body: some View {
        RenderView { _, drawableSize in
            let aspect = drawableSize.height > 0 ? Float(drawableSize.width / drawableSize.height) : 1.0
            let projectionMatrix = float4x4.perspective(fovY: .pi / 4, aspect: aspect, near: 0.1, far: 1_000.0)
            let viewMatrix = cameraMatrix.inverse
            let viewProjectionMatrix = projectionMatrix * viewMatrix

            try RenderPass(label: "Debug") {
                GridShader(
                    projectionMatrix: projectionMatrix,
                    cameraMatrix: cameraMatrix,
                    highlightedLines: [
                        .init(axis: .x, position: 0, width: 0.03, color: [1, 0.2, 0.2, 1]),
                        .init(axis: .y, position: 0, width: 0.03, color: [0.2, 0.4, 1, 1])
                    ],
                    backfaceColor: [1, 0, 0, 1]
                )

                try DebugRenderPipeline(
                    modelMatrix: .identity,
                    normalMatrix: .init(diagonal: [1, 1, 1]),
                    debugMode: debugMode,
                    lightPosition: [0, 10, 0],
                    cameraPosition: cameraMatrix.translation,
                    viewProjectionMatrix: viewProjectionMatrix
                ) {
                    Draw { encoder in
                        encoder.setVertexBuffers(of: teapot)
                        encoder.draw(teapot)
                    }
                }
                .vertexDescriptor(teapot.vertexDescriptor)
                .depthCompare(function: .less, enabled: true)
            }
        }
        .metalDepthStencilPixelFormat(.depth32Float)
        .interactiveCamera(rotation: $cameraRotation, distance: $cameraDistance, target: $cameraTarget)
        .frameTimingOverlay()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showInspector.toggle() } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
            }
        }
        .inspector(isPresented: $showInspector) {
            Form {
                DebugModePicker(debugMode: $debugMode)
            }
            .inspectorColumnWidth(min: 250, ideal: 300, max: 400)
        }
    }
}

private struct DebugModePicker: View {
    @Binding var debugMode: DebugShadersMode

    let debugModes: [(DebugShadersMode, String)] = [
        (.normal, "Normal"),
        (.texCoord, "Texture Coordinates"),
        (.tangent, "Tangent"),
        (.bitangent, "Bitangent"),
        (.worldPosition, "World Position"),
        (.localPosition, "Local Position"),
        (.uvDistortion, "UV Distortion"),
        (.tbnMatrix, "TBN Matrix"),
        (.vertexID, "Vertex ID"),
        (.faceNormal, "Face Normal"),
        (.uvDerivatives, "UV Derivatives"),
        (.checkerboard, "Checkerboard"),
        (.uvGrid, "UV Grid"),
        (.depth, "Depth"),
        (.wireframeOverlay, "Wireframe Overlay"),
        (.normalDeviation, "Normal Deviation"),
        (.amplificationID, "Amplification ID"),
        (.instanceID, "Instance ID"),
        (.quadThread, "Quad Thread"),
        (.simdGroup, "SIMD Group"),
        (.barycentricCoord, "Barycentric Coord"),
        (.frontFacing, "Front Facing"),
        (.sampleID, "Sample ID"),
        (.pointCoord, "Point Coord"),
        (.distanceToLight, "Distance to Light"),
        (.distanceToOrigin, "Distance to Origin"),
        (.distanceToCamera, "Distance to Camera")
    ]

    var body: some View {
        Picker("Debug Mode", selection: $debugMode) {
            ForEach(debugModes, id: \.0) { mode, label in
                Text(label).tag(mode)
            }
        }
        .pickerStyle(.menu)
    }
}

#Preview {
    DebugShaderDemoView()
}
