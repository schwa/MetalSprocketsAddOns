@preconcurrency import MetalSprockets

internal extension ShaderLibrary {
    static var module: ShaderLibrary {
        // swiftlint:disable:next force_try
        try! ShaderLibrary(bundle: .metalSprocketsAddOnsShaders())
    }
}
