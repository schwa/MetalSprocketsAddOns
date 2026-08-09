// Tests for the shared ViewTransforms/Transforms vocabulary: the derived matrix
// products every pipeline used to compute for itself.

import GeometryLite3D
@testable import MetalSprocketsAddOns
import simd
import Testing

private func expectClose(_ lhs: float4x4, _ rhs: float4x4, tolerance: Float = 1e-5, sourceLocation: SourceLocation = #_sourceLocation) {
    for column in 0..<4 {
        for row in 0..<4 {
            #expect(abs(lhs[column][row] - rhs[column][row]) < tolerance, sourceLocation: sourceLocation)
        }
    }
}

private let sampleProjection = float4x4.perspective(aspectRatio: 1.5, fovy: .pi / 3, near: 0.1, far: 100)
private let sampleCamera = LookAt(position: [1, 2, 5], target: [0, 1, 0], up: [0, 1, 0]).cameraMatrix
private let sampleModel = float4x4(translation: [3, -1, 2]) * float4x4(simd_quatf(angle: 0.7, axis: normalize([1, 2, 3])))

// MARK: - ViewTransforms

@Test
func testViewTransforms_viewMatrixIsInverseOfCameraMatrix() {
    let transforms = ViewTransforms(projectionMatrix: sampleProjection, cameraMatrix: sampleCamera)
    expectClose(transforms.viewMatrix, sampleCamera.inverse)
    expectClose(transforms.cameraMatrix * transforms.viewMatrix, matrix_identity_float4x4)
}

@Test
func testViewTransforms_initWithViewMatrixRoundTrips() {
    let viewMatrix = sampleCamera.inverse
    let transforms = ViewTransforms(projectionMatrix: sampleProjection, viewMatrix: viewMatrix)
    expectClose(transforms.cameraMatrix, sampleCamera)
    expectClose(transforms.viewMatrix, viewMatrix)
}

@Test
func testViewTransforms_initWithLookAtMatchesLookAtCameraMatrix() {
    let lookAt = LookAt(position: [0, 0, 4], target: .zero, up: [0, 1, 0])
    let transforms = ViewTransforms(projectionMatrix: sampleProjection, lookAt: lookAt)
    expectClose(transforms.cameraMatrix, lookAt.cameraMatrix)
    expectClose(transforms.viewMatrix, lookAt.viewMatrix)
}

@Test
func testViewTransforms_cameraPositionIsCameraTranslation() {
    let transforms = ViewTransforms(projectionMatrix: sampleProjection, cameraMatrix: sampleCamera)
    let position = transforms.cameraPosition
    #expect(abs(position.x - 1) < 1e-5)
    #expect(abs(position.y - 2) < 1e-5)
    #expect(abs(position.z - 5) < 1e-5)
}

@Test
func testViewTransforms_viewProjectionAndItsInverseAreConsistent() {
    let transforms = ViewTransforms(projectionMatrix: sampleProjection, cameraMatrix: sampleCamera)
    expectClose(transforms.viewProjectionMatrix, sampleProjection * sampleCamera.inverse)
    expectClose(transforms.viewProjectionMatrix * transforms.inverseViewProjectionMatrix, matrix_identity_float4x4, tolerance: 1e-3)
}

// MARK: - Transforms

@Test
func testTransforms_defaultModelMatrixIsIdentity() {
    let transforms = Transforms(projectionMatrix: sampleProjection, cameraMatrix: sampleCamera)
    expectClose(transforms.modelMatrix, matrix_identity_float4x4)
    expectClose(transforms.modelViewProjectionMatrix, transforms.viewProjectionMatrix)
}

@Test
func testTransforms_modelViewAndModelViewProjection() {
    let transforms = Transforms(projectionMatrix: sampleProjection, cameraMatrix: sampleCamera, modelMatrix: sampleModel)
    expectClose(transforms.modelViewMatrix, sampleCamera.inverse * sampleModel)
    expectClose(transforms.modelViewProjectionMatrix, sampleProjection * sampleCamera.inverse * sampleModel)
}

@Test
func testTransforms_normalMatrixIsUpperLeftOfModelMatrix() {
    let transforms = Transforms(projectionMatrix: sampleProjection, cameraMatrix: sampleCamera, modelMatrix: sampleModel)
    let normalMatrix = transforms.normalMatrix
    for column in 0..<3 {
        for row in 0..<3 {
            #expect(abs(normalMatrix[column][row] - sampleModel[column][row]) < 1e-5)
        }
    }
}

@Test
func testTransforms_normalMatrixRotatesNormalsIntoWorldSpace() {
    // A rotation-only model matrix should rotate a normal exactly as it rotates a direction.
    let rotation = float4x4(simd_quatf(angle: .pi / 2, axis: [0, 1, 0]))
    let transforms = Transforms(projectionMatrix: sampleProjection, cameraMatrix: sampleCamera, modelMatrix: rotation)
    let rotated = transforms.normalMatrix * SIMD3<Float>(0, 0, 1)
    let expected = (rotation * SIMD4<Float>(0, 0, 1, 0)).xyz
    #expect(simd_length(rotated - expected) < 1e-5)
}

@Test
func testTransforms_replacingModelMatrixKeepsCamera() {
    let transforms = Transforms(projectionMatrix: sampleProjection, cameraMatrix: sampleCamera, modelMatrix: sampleModel)
    let other = float4x4(translation: [9, 9, 9])
    let replaced = transforms.replacing(modelMatrix: other)
    #expect(replaced.view == transforms.view)
    expectClose(replaced.modelMatrix, other)
}

@Test
func testViewTransforms_transformsWithModelMatrixMatchesDirectInit() {
    let viewTransforms = ViewTransforms(projectionMatrix: sampleProjection, cameraMatrix: sampleCamera)
    let combined = viewTransforms.transforms(modelMatrix: sampleModel)
    let direct = Transforms(projectionMatrix: sampleProjection, cameraMatrix: sampleCamera, modelMatrix: sampleModel)
    #expect(combined == direct)
}

// MARK: - Matrix helpers

@Test
func testFloat4x4_lookAt_matchesLookAtViewMatrix() {
    let eye = SIMD3<Float>(2, 3, 4)
    let target = SIMD3<Float>(0, 1, 0)
    let up = SIMD3<Float>(0, 1, 0)
    expectClose(.lookAt(eye: eye, target: target, up: up), LookAt(position: eye, target: target, up: up).viewMatrix)
}

@Test
func testFloat4x4_lookAt_defaultUpIsYAxis() {
    let eye = SIMD3<Float>(0, 0, 5)
    expectClose(.lookAt(eye: eye, target: .zero), .lookAt(eye: eye, target: .zero, up: [0, 1, 0]))
}
