#if os(visionOS)
import Metal
import MetalKit
import MetalSprockets
import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsUI
import MetalSupport
import simd

/// The Shadow Map demo in the immersive space. The compositor's attachments can't be darkened from compute, so the
/// scene is drawn for both eyes into offscreen array textures, masked there, then composited into the compositor's pass.
enum ImmersiveShadowMapDemo {
    struct Model {
        var mesh: MTKMesh
        var transform: simd_float4x4
        var material: BlinnPhongMaterial
    }

    nonisolated(unsafe) private static let scene = ShadowMapDemoScene()

    // Read-only after creation.
    nonisolated(unsafe) static let models: [Model] = [
        Model(mesh: scene.sphere, transform: scene.sphereTransform, material: material(color: [0.85, 0.4, 0.3])),
        Model(mesh: scene.box, transform: scene.boxTransform, material: material(color: [0.3, 0.5, 0.9])),
        // MTKMesh.plane's normals face -Z; turned this way the ground faces up so it is lit.
        Model(mesh: scene.ground, transform: simd_float4x4(simd_quatf(angle: .pi / 2, axis: [1, 0, 0])), material: material(color: [0.8, 0.8, 0.82]))
    ]

    // Each frame updates the light; the render loop is one actor.
    nonisolated(unsafe) static let lighting = try? Lighting(
        ambientLightColor: [0.15, 0.15, 0.18],
        lights: [([0, 0, 0], Light(type: .point, color: [1, 1, 1], intensity: 3))]
    )

    nonisolated(unsafe) static let shadowMap = try? ShadowMap(resolution: 2_048)

    // One set, reused every frame. Frames in flight share it, which can show a stale frame.
    nonisolated(unsafe) static let textures = LayeredSceneTextures()

    private static func material(color: SIMD3<Float>) -> BlinnPhongMaterial {
        BlinnPhongMaterial(ambient: .color(color * 0.3), diffuse: .color(color), specular: .color([0.3, 0.3, 0.3]), shininess: 32)
    }

    /// The demo's scene, scaled like the other immersive demos and dropped so the ground is below eye height.
    static func world(_ context: ImmersiveContext) -> float4x4 {
        ImmersiveDemoShared.world(context) * float4x4(translation: [0, -1.5, 0])
    }

    /// The compositor's views with each viewport moved to the origin, for drawing into one array slice per view.
    static func offscreenViews(_ views: StereoViews) -> StereoViews {
        let viewports = views.viewports.map { MTLViewport(originX: 0, originY: 0, width: $0.width, height: $0.height, znear: $0.znear, zfar: $0.zfar) }
        return StereoViews(viewMatrices: views.viewMatrices, projectionMatrices: views.projectionMatrices, viewports: viewports)
    }

    static func layeredTextures(_ context: ImmersiveContext) throws -> (color: MTLTexture, depth: MTLTexture) {
        let viewport = context.viewports[0]
        return try textures.textures(width: Int(viewport.width), height: Int(viewport.height), arrayLength: context.viewCount)
    }

    /// Offscreen: the shadow map, the scene for both eyes, and the layered shadow mask.
    static func prepass(_ context: ImmersiveContext) throws -> some Element {
        var shadowMap = try shadowMap.orThrow(.resourceCreationFailure("Failed to create the immersive shadow map"))
        let lighting = try lighting.orThrow(.resourceCreationFailure("Failed to create the immersive shadow map lighting"))
        let first = models[0]
        let world = world(context)
        let scale = ImmersiveDemoShared.placementScale
        let lightPosition = (world * SIMD4(ShadowMapDemoScene.lightPosition(at: Float(context.time)), 1)).xyz
        lighting.setLightPosition(lightPosition, at: 0)
        shadowMap.updateDirectionalLight(at: 0, position: lightPosition, target: world.columns.3.xyz, orthoSize: 8 * scale, near: 0.1 * scale, far: 30 * scale)
        let views = offscreenViews(ImmersiveDemoShared.views(context))
        let (color, depth) = try layeredTextures(context)
        let shadowContext = try ShadowContext(views: views, colorTexture: color, depthTexture: depth)
        let technique = ShadowMapTechnique(shadowMap: shadowMap, vertexDescriptor: first.mesh.vertexDescriptor) {
            ForEach(Array(models.enumerated()), id: \.offset) { _, model in
                Draw(mesh: model.mesh)
                    .vertexBuffers(of: model.mesh)
                    .parameter("modelMatrix", functionType: .vertex, value: world * model.transform)
            }
        }
        let cameraMatrix = views.cameraMatrices[0]
        return try ShadowedScene(technique: technique, context: shadowContext) {
            try RenderPass(label: "Immersive Shadow Map Scene") {
                try BlinnPhongShader(viewCount: views.count) {
                    try ForEach(Array(models.enumerated()), id: \.offset) { _, model in
                        try Draw { encoder in
                            views.configure(encoder)
                            encoder.draw(model.mesh)
                        }
                        .vertexBuffers(of: model.mesh)
                        .useResources(model.mesh.submeshes.map(\.indexBuffer.buffer), usage: .read, stages: .vertex)
                        .blinnPhongMaterial(model.material)
                        .blinnPhongMatrices(modelMatrix: world * model.transform, cameraMatrix: cameraMatrix, views: views)
                    }
                    .lighting(lighting)
                }
                .vertexDescriptor(first.mesh.vertexDescriptor)
                .depthCompare(function: .greater, writes: true)
            }
            .renderPassDescriptorModifier { descriptor in
                descriptor.colorAttachments[0].texture = color
                descriptor.colorAttachments[0].loadAction = .clear
                descriptor.colorAttachments[0].storeAction = .store
                descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
                // Reverse Z, like the compositor; the composite skips pixels left at the clear depth.
                descriptor.depthAttachment.texture = depth
                descriptor.depthAttachment.loadAction = .clear
                descriptor.depthAttachment.storeAction = .store
                descriptor.depthAttachment.clearDepth = 0
                descriptor.stencilAttachment.texture = nil
                descriptor.renderTargetArrayLength = color.arrayLength
                descriptor.rasterizationRateMap = nil
            }
        }
    }

    /// In the compositor's pass: the shadowed scene, with its depth.
    static func composite(_ context: ImmersiveContext) throws -> some Element {
        let (color, depth) = try layeredTextures(context)
        return try LayeredCompositeRenderPipeline(color: color, depth: depth, views: ImmersiveDemoShared.views(context), clearDepth: 0, depthCompareFunction: .greater)
    }
}

/// Offscreen colour and depth arrays, one slice per view, recreated when the size changes.
final class LayeredSceneTextures {
    private var color: MTLTexture?
    private var depth: MTLTexture?

    func textures(width: Int, height: Int, arrayLength: Int) throws -> (color: MTLTexture, depth: MTLTexture) {
        if let color, let depth, color.width == width, color.height == height, color.arrayLength == arrayLength {
            return (color, depth)
        }
        let device = _MTLCreateSystemDefaultDevice()
        func make(_ format: MTLPixelFormat, usage: MTLTextureUsage, label: String) throws -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: max(width, 1), height: max(height, 1), mipmapped: false)
            descriptor.textureType = .type2DArray
            descriptor.arrayLength = arrayLength
            descriptor.usage = usage
            descriptor.storageMode = .private
            let texture = try device.makeTexture(descriptor: descriptor).orThrow(.resourceCreationFailure("Failed to create \(label)"))
            texture.label = label
            return texture
        }
        let color = try make(.rgba16Float, usage: ShadowContext.requiredColorUsage, label: "Layered Scene Color")
        let depth = try make(.depth32Float, usage: ShadowContext.requiredDepthUsage, label: "Layered Scene Depth")
        self.color = color
        self.depth = depth
        return (color, depth)
    }
}
#endif
