import GeometryLite3D
import simd
import SwiftUI

/// A turntable camera: yaw/pitch around a target at a fixed distance.
public struct OrbitCamera: Equatable {
    public var yaw: Float
    public var pitch: Float
    public var distance: Float
    public var target: SIMD3<Float>

    public init(yaw: Float = 0, pitch: Float = -.pi / 8, distance: Float = 6, target: SIMD3<Float> = .zero) {
        self.yaw = yaw
        self.pitch = pitch
        self.distance = distance
        self.target = target
    }

    /// Camera-to-world matrix.
    public var cameraMatrix: simd_float4x4 {
        let rotation = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: pitch, axis: [1, 0, 0])
        return float4x4(translation: target) * float4x4(rotation) * float4x4(translation: [0, 0, distance])
    }

    public var viewMatrix: simd_float4x4 { cameraMatrix.inverse }

    public var position: SIMD3<Float> {
        let column = cameraMatrix.columns.3
        return [column.x, column.y, column.z]
    }

    public func projectionMatrix(drawableSize: CGSize, zClip: ClosedRange<Float> = 0.1...200) -> simd_float4x4 {
        let aspect = drawableSize.height > 0 ? Float(drawableSize.width / drawableSize.height) : 1
        return PerspectiveProjection(verticalAngleOfView: .degrees(60), depthMode: .standard(zClip: zClip))
            .projectionMatrix(aspectRatio: aspect)
    }
}

public extension View {
    /// Drag to orbit, pinch (or scroll) to dolly.
    func orbitCamera(_ camera: Binding<OrbitCamera>) -> some View {
        modifier(OrbitCameraModifier(camera: camera))
    }
}

private struct OrbitCameraModifier: ViewModifier {
    @Binding var camera: OrbitCamera

    @State private var dragStart: OrbitCamera?
    @State private var zoomStart: Float?

    func body(content: Content) -> some View {
        content
            .contentShape(.rect)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let start = dragStart ?? camera
                        dragStart = start
                        camera.yaw = start.yaw - Float(value.translation.width) * 0.01
                        // Clamped just short of the poles so the up vector never degenerates.
                        camera.pitch = (start.pitch - Float(value.translation.height) * 0.01)
                            .clamped(to: -.pi / 2 + 0.01 ... .pi / 2 - 0.01)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let start = zoomStart ?? camera.distance
                        zoomStart = start
                        camera.distance = (start / Float(value.magnification)).clamped(to: 0.5...200)
                    }
                    .onEnded { _ in zoomStart = nil }
            )
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
