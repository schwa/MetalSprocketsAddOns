import GeometryLite3D
import simd

// MARK: - ViewTransforms

/// The camera half of a render pipeline's transform state: a projection matrix and a
/// camera (camera-to-world) matrix, plus the products pipelines derive from them.
///
/// Pipelines take `ViewTransforms` when they draw something that has no model matrix of
/// its own (skyboxes, grids, full-screen shadow passes).
public struct ViewTransforms: Equatable, Sendable {
    /// Clip-from-view matrix.
    public var projectionMatrix: float4x4

    /// World-from-camera matrix. Its inverse is the view matrix.
    public var cameraMatrix: float4x4

    public init(projectionMatrix: float4x4, cameraMatrix: float4x4) {
        self.projectionMatrix = projectionMatrix
        self.cameraMatrix = cameraMatrix
    }

    /// Creates view transforms from a view (camera-from-world) matrix.
    public init(projectionMatrix: float4x4, viewMatrix: float4x4) {
        self.init(projectionMatrix: projectionMatrix, cameraMatrix: viewMatrix.inverse)
    }

    /// Creates view transforms from a `GeometryLite3D` look-at description.
    public init(projectionMatrix: float4x4, lookAt: LookAt) {
        self.init(projectionMatrix: projectionMatrix, cameraMatrix: lookAt.cameraMatrix)
    }
}

public extension ViewTransforms {
    /// Camera-from-world matrix.
    var viewMatrix: float4x4 {
        cameraMatrix.inverse
    }

    /// World-space position of the camera.
    var cameraPosition: SIMD3<Float> {
        cameraMatrix.translation
    }

    /// Clip-from-world matrix.
    var viewProjectionMatrix: float4x4 {
        projectionMatrix * viewMatrix
    }

    /// World-from-clip matrix, used to unproject depth samples.
    var inverseViewProjectionMatrix: float4x4 {
        viewProjectionMatrix.inverse
    }

    /// Combines these view transforms with a model matrix.
    func transforms(modelMatrix: float4x4) -> Transforms {
        Transforms(view: self, modelMatrix: modelMatrix)
    }
}

// MARK: - Transforms

/// The full transform state for drawing one model: projection, camera, and model matrices,
/// plus every product pipelines derive from them.
///
/// This is the shared vocabulary for pipelines that used to each invent their own set of
/// matrix parameters.
public struct Transforms: Equatable, Sendable {
    /// The camera half of the transform state.
    public var view: ViewTransforms

    /// World-from-model matrix.
    public var modelMatrix: float4x4

    public init(view: ViewTransforms, modelMatrix: float4x4 = matrix_identity_float4x4) {
        self.view = view
        self.modelMatrix = modelMatrix
    }

    public init(projectionMatrix: float4x4, cameraMatrix: float4x4, modelMatrix: float4x4 = matrix_identity_float4x4) {
        self.init(view: .init(projectionMatrix: projectionMatrix, cameraMatrix: cameraMatrix), modelMatrix: modelMatrix)
    }

    public init(projectionMatrix: float4x4, viewMatrix: float4x4, modelMatrix: float4x4 = matrix_identity_float4x4) {
        self.init(view: .init(projectionMatrix: projectionMatrix, viewMatrix: viewMatrix), modelMatrix: modelMatrix)
    }
}

public extension Transforms {
    var projectionMatrix: float4x4 { view.projectionMatrix }
    var cameraMatrix: float4x4 { view.cameraMatrix }
    var viewMatrix: float4x4 { view.viewMatrix }
    var cameraPosition: SIMD3<Float> { view.cameraPosition }
    var viewProjectionMatrix: float4x4 { view.viewProjectionMatrix }
    var inverseViewProjectionMatrix: float4x4 { view.inverseViewProjectionMatrix }

    /// Camera-from-model matrix.
    var modelViewMatrix: float4x4 {
        viewMatrix * modelMatrix
    }

    /// Clip-from-model matrix.
    var modelViewProjectionMatrix: float4x4 {
        projectionMatrix * modelViewMatrix
    }

    /// Matrix used to rotate normals into world space.
    ///
    /// This is the upper-left 3×3 of the model matrix, which is correct for rigid transforms
    /// and uniform scale only. Non-uniform scale needs an inverse-transpose; pipelines here
    /// have always used the cheap form, so it is kept for compatibility.
    var normalMatrix: float3x3 {
        float3x3(
            modelMatrix.columns.0.xyz,
            modelMatrix.columns.1.xyz,
            modelMatrix.columns.2.xyz
        )
    }

    /// Returns a copy with a different model matrix, reusing the camera transforms.
    func replacing(modelMatrix: float4x4) -> Transforms {
        Transforms(view: view, modelMatrix: modelMatrix)
    }
}

// MARK: - Matrix helpers

public extension float4x4 {
    /// Creates a look-at view (camera-from-world) matrix.
    static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float> = [0, 1, 0]) -> float4x4 {
        LookAt(position: eye, target: target, up: up).viewMatrix
    }

    /// Creates an orthographic projection matrix.
    /// - Parameter inverseZ: When true, near maps to 1.0 and far maps to 0.0 (reversed depth).
    static func orthographic(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float, inverseZ: Bool = true) -> float4x4 {
        let sx = 2.0 / (right - left)
        let sy = 2.0 / (top - bottom)
        let sz: Float
        let tz: Float
        if inverseZ {
            sz = 1.0 / (far - near)
            tz = far / (far - near)
        } else {
            sz = 1.0 / (near - far)
            tz = near / (near - far)
        }
        let tx = -(right + left) / (right - left)
        let ty = -(top + bottom) / (top - bottom)

        return float4x4(columns: (
            SIMD4(sx, 0, 0, 0),
            SIMD4(0, sy, 0, 0),
            SIMD4(0, 0, sz, 0),
            SIMD4(tx, ty, tz, 1)
        ))
    }
}
