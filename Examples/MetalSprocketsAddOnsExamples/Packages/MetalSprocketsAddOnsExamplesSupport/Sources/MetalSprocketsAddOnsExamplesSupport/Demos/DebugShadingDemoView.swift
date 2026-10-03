import GeometryLite3D
import Metal
import MetalKit
import MetalSprockets
import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsUI
import MetalSupport
import ModelIO
import simd
import SwiftUI

/// `DebugRenderPipeline` renders a single vertex attribute straight to the colour target.
///
/// This is the fastest way to answer "is my vertex descriptor lying to me?": if normals show
/// as noise instead of a smooth gradient, or UVs are not a clean two-channel ramp, the buffer
/// layout and the descriptor disagree. The mesh here is built with an explicit interleaved
/// tangent-basis layout so every attribute lands in vertex buffer 0.
struct DebugShadingDemoView: View {
    @State private var camera = OrbitCamera(pitch: -.pi / 8, distance: 4)
    @State private var debugMode: DebugShadersMode = .normal
    @State private var wireframe = false
    @State private var useSphere = true

    private let scene = DebugShadingDemoScene()

    var body: some View {
        DemoLayout {
            RenderView { _, drawableSize in
                try scene.element(
                    useSphere: useSphere,
                    debugMode: debugMode,
                    wireframe: wireframe,
                    camera: camera,
                    projection: camera.projectionMatrix(drawableSize: drawableSize)
                )
            }
            .metalDepthStencilPixelFormat(.depth32Float)
            .metalClearColor(DebugShadingDemoScene.clearColor)
            .orbitCamera($camera)
        } controls: {
            Picker("Mode", selection: $debugMode) {
                ForEach(DebugShadersMode.allDemoCases, id: \.rawValue) { mode in
                    Text(mode.demoName).tag(mode)
                }
            }
            .pickerStyle(.inline)
            Toggle("Sphere", isOn: $useSphere)
            Toggle("Wireframe", isOn: $wireframe)
        }
    }
}

/// The demo's meshes and per-frame scene, separate from the view so tests can render it offscreen.
struct DebugShadingDemoScene {
    static let clearColor = MTLClearColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1)

    let sphere = makeTangentBasisMesh(.sphere)
    let box = makeTangentBasisMesh(.box)

    func element(
        useSphere: Bool,
        debugMode: DebugShadersMode,
        wireframe: Bool,
        camera: OrbitCamera,
        projection: simd_float4x4
    ) throws -> some Element {
        let mesh = useSphere ? sphere : box
        return try RenderPass {
            try DebugRenderPipeline(
                modelMatrix: matrix_identity_float4x4,
                normalMatrix: matrix_identity_float3x3,
                debugMode: debugMode,
                lightPosition: [3, 4, 3],
                cameraPosition: camera.position,
                viewProjectionMatrix: projection * camera.viewMatrix
            ) {
                Draw { encoder in
                    if wireframe {
                        encoder.setTriangleFillMode(.lines)
                    }
                    encoder.draw(mesh)
                }
                .vertexBuffers(of: mesh)
                .useResources(mesh.submeshes.map(\.indexBuffer.buffer), usage: .read, stages: .vertex)
            }
            .vertexDescriptor(mesh.vertexDescriptor)
            .depthCompare(function: .less, enabled: true)
        }
    }
}

// MARK: - Mesh

private enum DemoShape {
    case sphere
    case box
}

/// Builds a mesh whose position, normal, texture coordinate, tangent and bitangent are all
/// interleaved into vertex buffer 0.
///
/// Model I/O's `addTangentBasis` otherwise spreads attributes across several buffers, and
/// `vertexBuffers(of:)` then binds those at vertex buffer indices 1, 2, … — clobbering the
/// uniform buffers the debug shaders declare at exactly those indices.
private func makeTangentBasisMesh(_ shape: DemoShape) -> MTKMesh {
    let device = _MTLCreateSystemDefaultDevice()
    let allocator = MTKMeshBufferAllocator(device: device)
    let mdlMesh: MDLMesh
    switch shape {
    case .sphere:
        mdlMesh = MDLMesh(
            sphereWithExtent: [1, 1, 1],
            segments: [32, 32],
            inwardNormals: false,
            geometryType: .triangles,
            allocator: allocator
        )
    case .box:
        mdlMesh = MDLMesh(
            boxWithExtent: [1.2, 1.2, 1.2],
            segments: [1, 1, 1],
            inwardNormals: false,
            geometryType: .triangles,
            allocator: allocator
        )
    }
    // The primitives already have normals. Regenerating them with a crease threshold of 0 gives
    // zero-length normals on the degenerate triangles at the sphere poles, which leaves holes.
    mdlMesh.addTangentBasis(
        forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
        tangentAttributeNamed: MDLVertexAttributeTangent,
        bitangentAttributeNamed: MDLVertexAttributeBitangent
    )

    let descriptor = MDLVertexDescriptor()
    let attributes: [(String, MDLVertexFormat, Int)] = [
        (MDLVertexAttributePosition, .float3, 0),
        (MDLVertexAttributeNormal, .float3, 12),
        (MDLVertexAttributeTextureCoordinate, .float2, 24),
        (MDLVertexAttributeTangent, .float3, 32),
        (MDLVertexAttributeBitangent, .float3, 44)
    ]
    descriptor.attributes = NSMutableArray(array: attributes.map { name, format, offset in
        MDLVertexAttribute(name: name, format: format, offset: offset, bufferIndex: 0)
    })
    descriptor.layouts = NSMutableArray(array: [MDLVertexBufferLayout(stride: 56)])
    mdlMesh.vertexDescriptor = descriptor

    // swiftlint:disable:next force_try
    return try! MTKMesh(mesh: mdlMesh, device: device)
}

// MARK: - Modes

private extension DebugShadersMode {
    static let allDemoCases: [DebugShadersMode] = [
        .normal, .faceNormal, .tangent, .bitangent, .texCoord, .uvGrid,
        .localPosition, .worldPosition, .depth, .barycentricCoord, .frontFacing
    ]

    var demoName: String {
        switch self {
        case .normal: "Normal"
        case .faceNormal: "Face Normal"
        case .tangent: "Tangent"
        case .bitangent: "Bitangent"
        case .texCoord: "Texture Coordinate"
        case .uvGrid: "UV Grid"
        case .localPosition: "Local Position"
        case .worldPosition: "World Position"
        case .depth: "Depth"
        case .barycentricCoord: "Barycentric"
        case .frontFacing: "Front Facing"
        default: "Mode \(rawValue)"
        }
    }
}

#Preview {
    DebugShadingDemoView()
}
