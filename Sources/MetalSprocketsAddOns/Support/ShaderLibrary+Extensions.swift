@preconcurrency import MetalSprockets

internal extension ShaderLibrary {
    static var module: ShaderLibrary {
        get {
            try! ShaderLibrary(bundle: .metalSprocketsAddOnsShaders())
        }
    }
}
