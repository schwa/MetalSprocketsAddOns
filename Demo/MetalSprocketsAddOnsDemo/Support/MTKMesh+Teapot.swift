import MetalKit
import MetalSprocketsSupport

extension MTKMesh {
    static func teapot(options: MTKMesh.Options = []) -> MTKMesh {
        do {
            return try MTKMesh(name: "teapot", bundle: .main, options: options)
        } catch {
            fatalError("Failed to load teapot mesh: \(error)")
        }
    }
}
