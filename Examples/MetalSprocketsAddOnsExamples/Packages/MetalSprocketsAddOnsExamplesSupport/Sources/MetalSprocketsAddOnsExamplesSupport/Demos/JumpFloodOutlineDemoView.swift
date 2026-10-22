import Interaction3D
import Metal
import MetalKit
import MetalSprockets
import MetalSprocketsAddOns
import MetalSprocketsUI
import MetalSupport
import simd
import SwiftMesh
import SwiftUI

/// Wide outlines with the jump flood algorithm.
///
/// 1. `SilhouetteMaskRenderPipeline` draws the selected models into an R8 mask.
/// 2. `JumpFloodPipeline` finds, for each pixel, the nearest masked pixel.
/// 3. The scene is drawn normally.
/// 4. `JumpFloodOutlineRenderPipeline` blends the outline over the scene.
///
/// The cost does not depend much on the outline width: a 300 px outline needs only a few more passes than a 10 px one.
struct JumpFloodOutlineDemoView: View {
    @State private var camera = InteractionState(pitch: -.pi / 7, distance: 8, target: [0, 0.5, 0])
    @State private var outlineWidth: Float = 12
    @State private var outlineColor = Color.orange
    @State private var outlineSphere = true
    @State private var outlineBox = true
    @State private var xray = true

    private let scene = JumpFloodOutlineDemoScene()

    var body: some View {
        DemoLayoutView {
            RenderView { _, drawableSize in
                let projection = camera.projectionMatrix(drawableSize: drawableSize)
                try scene.element(
                    viewProjection: projection * camera.viewMatrix,
                    drawableSize: drawableSize,
                    outlined: outlinedModels,
                    outlineColor: outlineColor.demoSIMD4,
                    outlineWidth: outlineWidth,
                    xray: xray
                )
            }
            .metalDepthStencilPixelFormat(.depth32Float)
            // Later passes load the scene depth, so it can't be memoryless.
            .metalDepthStencilStorageMode(.private)
            .metalClearColor(JumpFloodOutlineDemoScene.clearColor)
            .demoCameraControls($camera)
        } controls: {
            Toggle("Outline Sphere", isOn: $outlineSphere)
            Toggle("Outline Box", isOn: $outlineBox)
            Toggle("X-ray", isOn: $xray)
            LabeledContent("Width \(Int(outlineWidth)) px") {
                Slider(value: $outlineWidth, in: 0...300)
            }
            ColorPicker("Color", selection: $outlineColor)
        }
    }

    private var outlinedModels: Set<JumpFloodOutlineDemoScene.Model> {
        var models: Set<JumpFloodOutlineDemoScene.Model> = []
        if outlineSphere {
            models.insert(.sphere)
        }
        if outlineBox {
            models.insert(.box)
        }
        return models
    }
}

/// The demo's models and per-frame scene, separate from the view so tests can render it offscreen.
struct JumpFloodOutlineDemoScene {
    enum Model: CaseIterable, Hashable {
        case sphere
        case box
        case ground
    }

    static let clearColor = MTLClearColor(red: 0.05, green: 0.06, blue: 0.09, alpha: 1)

    let meshes: [Model: MTKMesh] = [
        .sphere: MTKMesh.sphere(extent: [0.8, 0.8, 0.8]),
        .box: MTKMesh.box(extent: [1, 2, 1]),
        .ground: MTKMesh.plane(width: 10, height: 10)
    ]
    let transforms: [Model: simd_float4x4] = [
        .sphere: simd_float4x4(translation: [-1.4, 0.8, 0]),
        .box: simd_float4x4(translation: [1.4, 1, 0]),
        // MTKMesh.plane is in the XY plane; lay it flat on y = 0.
        .ground: simd_float4x4(simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]))
    ]
    let colors: [Model: SIMD3<Float>] = [
        .sphere: [0.85, 0.4, 0.3],
        .box: [0.3, 0.5, 0.9],
        .ground: [0.7, 0.7, 0.72]
    ]
    private let metalMeshes: [Model: MetalMesh]
    private let textures = JumpFloodDemoTextures()

    init() {
        metalMeshes = meshes.mapValues { MetalMesh(mtkMesh: $0) }
    }

    func element(
        viewProjection: simd_float4x4,
        drawableSize: CGSize,
        outlined: Set<Model>,
        outlineColor: SIMD4<Float>,
        outlineWidth: Float,
        xray: Bool = true
    ) throws -> some Element {
        let (mask, seeds) = try textures.textures(width: Int(drawableSize.width), height: Int(drawableSize.height))
        let instances = Model.allCases.filter(outlined.contains).compactMap { model in
            metalMeshes[model].map { SilhouetteMaskRenderPipeline.Instance(mesh: $0, transform: transforms[model] ?? matrix_identity_float4x4) }
        }
        let models = Model.allCases.compactMap { model in
            meshes[model].map { (mesh: $0, transform: transforms[model] ?? matrix_identity_float4x4, color: colors[model] ?? [1, 1, 1]) }
        }
        return JumpFloodOutlineScene(
            models: models,
            instances: instances,
            viewProjection: viewProjection,
            mask: mask,
            seeds: seeds,
            outlineColor: outlineColor,
            outlineWidth: outlineWidth,
            xray: xray
        )
    }
}

/// Scene, then mask, flood and outline. With `xray` off, the outline is depth-tested against the scene, so objects
/// in front of an outlined model hide its outline.
private struct JumpFloodOutlineScene: Element {
    typealias Model = (mesh: MTKMesh, transform: simd_float4x4, color: SIMD3<Float>)

    var models: [Model]
    var instances: [SilhouetteMaskRenderPipeline.Instance]
    var viewProjection: simd_float4x4
    var mask: MTLTexture
    var seeds: MTLTexture
    var outlineColor: SIMD4<Float>
    var outlineWidth: Float
    var xray: Bool

    var body: some Element {
        get throws {
            let showOutline = !instances.isEmpty && outlineWidth > 0

            try RenderPass(label: "Scene") {
                ForEach(Array(models.enumerated()), id: \.offset) { _, model in
                    try FlatShader(modelViewProjection: viewProjection * model.transform, textureSpecifier: ColorSource.color(model.color)) {
                        Draw(mesh: model.mesh)
                            .vertexBuffers(of: model.mesh)
                    }
                    .vertexDescriptor(MTLVertexDescriptor(model.mesh.vertexDescriptor))
                    .depthCompare(function: .less, writes: true)
                }
            }
            .renderPassDescriptorModifier { descriptor in
                // The outline pass depth-tests against this.
                descriptor.depthAttachment.storeAction = .store
            }

            if showOutline {
                try RenderPass(label: "Silhouette Mask") {
                    SilhouetteMaskRenderPipeline(instances: instances, viewProjection: viewProjection)
                }
                .renderPassDescriptorModifier { descriptor in
                    descriptor.colorAttachments[0].texture = mask
                    descriptor.colorAttachments[0].loadAction = .clear
                    descriptor.colorAttachments[0].storeAction = .store
                    descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
                    descriptor.depthAttachment.texture = nil
                    descriptor.stencilAttachment.texture = nil
                }
                JumpFloodPipeline(mask: mask, seeds: seeds, maximumDistance: outlineWidth)

                try RenderPass(label: "Outline") {
                    JumpFloodOutlineRenderPipeline(
                        mask: mask,
                        seeds: seeds,
                        color: outlineColor,
                        width: outlineWidth,
                        depthCompareFunction: xray ? .always : .lessEqual
                    )
                }
                .renderPassDescriptorModifier { descriptor in
                    descriptor.colorAttachments[0].loadAction = .load
                    descriptor.depthAttachment.loadAction = .load
                }
            }
        }
    }
}

/// Mask and seed textures sized to the drawable, rebuilt when it changes.
private final class JumpFloodDemoTextures {
    private var mask: MTLTexture?
    private var seeds: MTLTexture?

    func textures(width: Int, height: Int) throws -> (mask: MTLTexture, seeds: MTLTexture) {
        let width = max(width, 1)
        let height = max(height, 1)
        if let mask, let seeds, mask.width == width, mask.height == height {
            return (mask, seeds)
        }
        let device = _MTLCreateSystemDefaultDevice()
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let mask = try device.makeTexture(descriptor: descriptor).orThrow(.resourceCreationFailure("Failed to create outline mask"))
        mask.label = "Outline Mask"
        let seeds = try JumpFloodPipeline.makeSeedTexture(device: device, width: width, height: height)
        self.mask = mask
        self.seeds = seeds
        return (mask, seeds)
    }
}

private extension Color {
    var demoSIMD4: SIMD4<Float> {
        let resolved = resolve(in: EnvironmentValues())
        return [resolved.red, resolved.green, resolved.blue, resolved.opacity]
    }
}

#Preview {
    JumpFloodOutlineDemoView()
}
