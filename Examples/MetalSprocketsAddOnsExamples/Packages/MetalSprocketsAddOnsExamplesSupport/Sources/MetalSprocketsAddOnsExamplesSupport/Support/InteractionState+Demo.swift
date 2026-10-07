import GeometryLite3D
import Interaction3D
import simd
import SwiftUI

// Camera math for the demos. Interaction3D's `interactiveCamera` drives the state; scenes and
// tests read matrices from it.
extension InteractionState {
    /// A turntable pose: yaw around world Y, then pitch around the camera's X.
    init(yaw: Float = 0, pitch: Float = -.pi / 8, distance: Float = 6, target: SIMD3<Float> = .zero) {
        let rotation = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: pitch, axis: [1, 0, 0])
        self.init(rotation: rotation, distance: distance, target: target)
    }

    /// Camera-to-world matrix.
    var cameraMatrix: simd_float4x4 {
        float4x4(translation: target) * float4x4(rotation) * float4x4(translation: [0, 0, distance])
    }

    var viewMatrix: simd_float4x4 { cameraMatrix.inverse }

    var position: SIMD3<Float> {
        let column = cameraMatrix.columns.3
        return [column.x, column.y, column.z]
    }

    func projectionMatrix(drawableSize: CGSize, zClip: ClosedRange<Float> = 0.1...200) -> simd_float4x4 {
        let aspect = drawableSize.height > 0 ? Float(drawableSize.width / drawableSize.height) : 1
        return PerspectiveProjection(verticalAngleOfView: .degrees(60), depthMode: .standard(zClip: zClip))
            .projectionMatrix(aspectRatio: aspect)
    }
}

extension View {
    /// Interaction3D orbit controls on a demo camera: drag to orbit, scroll or pinch to zoom,
    /// Command-drag to pan.
    func demoCameraControls(_ camera: Binding<InteractionState>) -> some View {
        interactiveCamera(
            rotation: camera.rotation,
            distance: camera.distance,
            target: camera.target,
            zoom: .multiplicative()
        )
    }
}
