// Tests for AccelerationStructureManager (RayTracedShadows.swift).
//
// Skips automatically on devices that do not support ray tracing.

import Foundation
import Metal
import MetalKit
@testable import MetalSprocketsAddOns
import MetalSprocketsSupport
import MetalSupport
import simd
import Testing

private func ensureRayTracingSupported() throws {
    let device = _MTLCreateSystemDefaultDevice()
    try #require(device.supportsRaytracing, "Ray tracing not supported on this device")
}

// MARK: - Instance struct

@Test
func testAccelerationStructureManager_Instance_init() {
    let m = float4x4(translation: SIMD3<Float>(1, 2, 3))
    let instance = AccelerationStructureManager.Instance(meshIndex: 5, transform: m)
    #expect(instance.meshIndex == 5)
    #expect(instance.transform == m)
}

// MARK: - Manager init

@Test(.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil, "Ray tracing unsupported on CI paravirt GPU — see issue #29"))
@MainActor
func testAccelerationStructureManager_init() throws {
    try ensureRayTracingSupported()
    let manager = try AccelerationStructureManager()
    #expect(manager.instanceAccelerationStructure == nil)
    #expect(manager.primitiveAccelerationStructures.isEmpty)
}

// MARK: - build()

@Test(.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil, "Ray tracing unsupported on CI paravirt GPU — see issue #29"))
@MainActor
func testAccelerationStructureManager_build_singleMeshSingleInstance() throws {
    try ensureRayTracingSupported()
    var manager = try AccelerationStructureManager()
    let mesh = MTKMesh.box(extent: [1, 1, 1])
    let instances = [
        AccelerationStructureManager.Instance(meshIndex: 0, transform: .init(diagonal: SIMD4<Float>(1, 1, 1, 1)))
    ]

    try manager.build(meshes: [mesh], instances: instances)

    #expect(manager.primitiveAccelerationStructures.count == 1)
    #expect(manager.instanceAccelerationStructure != nil)
}

@Test(.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil, "Ray tracing unsupported on CI paravirt GPU — see issue #29"))
@MainActor
func testAccelerationStructureManager_build_multipleMeshesAndInstances() throws {
    try ensureRayTracingSupported()
    var manager = try AccelerationStructureManager()
    let meshes = [
        MTKMesh.box(extent: [1, 1, 1]),
        MTKMesh.sphere(extent: [1, 1, 1])
    ]
    let instances = [
        AccelerationStructureManager.Instance(meshIndex: 0, transform: float4x4(translation: SIMD3<Float>(0, 0, 0))),
        AccelerationStructureManager.Instance(meshIndex: 1, transform: float4x4(translation: SIMD3<Float>(2, 0, 0))),
        AccelerationStructureManager.Instance(meshIndex: 0, transform: float4x4(translation: SIMD3<Float>(-2, 0, 0)))
    ]

    try manager.build(meshes: meshes, instances: instances)

    #expect(manager.primitiveAccelerationStructures.count == 2)
    #expect(manager.instanceAccelerationStructure != nil)
}

// MARK: - updateInstances() (refit path)

@Test(.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil, "Ray tracing unsupported on CI paravirt GPU — see issue #29"))
@MainActor
func testAccelerationStructureManager_updateInstances_afterBuild() throws {
    try ensureRayTracingSupported()
    var manager = try AccelerationStructureManager()
    let mesh = MTKMesh.box(extent: [1, 1, 1])
    let initial = [
        AccelerationStructureManager.Instance(meshIndex: 0, transform: float4x4(translation: SIMD3<Float>(0, 0, 0)))
    ]
    try manager.build(meshes: [mesh], instances: initial)

    let firstAS = manager.instanceAccelerationStructure
    #expect(firstAS != nil)

    // Refit with two instances of the same mesh — primitive structures should
    // be reused, only the instance acceleration structure rebuilt.
    let updated = [
        AccelerationStructureManager.Instance(meshIndex: 0, transform: float4x4(translation: SIMD3<Float>(1, 0, 0))),
        AccelerationStructureManager.Instance(meshIndex: 0, transform: float4x4(translation: SIMD3<Float>(-1, 0, 0)))
    ]
    try manager.updateInstances(updated)
    #expect(manager.primitiveAccelerationStructures.count == 1)
    #expect(manager.instanceAccelerationStructure != nil)
}

@Test(.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil, "Ray tracing unsupported on CI paravirt GPU — see issue #29"))
@MainActor
func testAccelerationStructureManager_updateInstances_beforeBuild_throws() throws {
    try ensureRayTracingSupported()
    var manager = try AccelerationStructureManager()

    #expect(throws: MetalSprocketsError.self) {
        try manager.updateInstances([
            AccelerationStructureManager.Instance(meshIndex: 0, transform: matrix_identity_float4x4)
        ])
    }
}
