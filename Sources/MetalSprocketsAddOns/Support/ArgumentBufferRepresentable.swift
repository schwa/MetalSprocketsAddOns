import Metal
import MetalSprockets

/// A type that can pack itself into an argument buffer and report the GPU resources that
/// argument buffer refers to.
///
/// Argument buffers hold resource IDs rather than references, so every resource named by an
/// argument buffer must be made resident with `useResource` before the draw that reads it.
/// Conforming types keep the packing and the residency list in one place so the two halves
/// cannot drift apart. Bind them with ``Element/argumentBuffer(_:value:functionTypes:usage:stages:)``
/// rather than pairing `parameter` and `useResource` by hand.
public protocol ArgumentBufferRepresentable {
    associatedtype ArgumentBuffer

    /// Pack the receiver into its argument buffer representation.
    func toArgumentBuffer() throws -> ArgumentBuffer

    /// Every GPU resource referenced by the argument buffer returned by ``toArgumentBuffer()``.
    var argumentBufferResources: [any MTLResource] { get }
}

public extension Element {
    /// Bind an argument-buffer-representable value to a shader parameter, making every resource
    /// it references resident for the given stages.
    func argumentBuffer(
        _ name: String,
        value: some ArgumentBufferRepresentable,
        functionTypes: FunctionTypes = [],
        usage: MTLResourceUsage = .read,
        stages: MTLRenderStages = .fragment
    ) throws -> some Element {
        self
            .parameter(name, functionTypes: functionTypes, value: try value.toArgumentBuffer())
            .useResources(value.argumentBufferResources, usage: usage, stages: stages)
    }
}
