#include "MetalSprocketsAddOnsShaders.h"

using namespace metal;

namespace SilhouetteMask {

    struct VertexOut {
        float4 position [[position]];
    };

    // Reads positions straight from the mesh buffer so any vertex layout works.
    [[vertex]] VertexOut vertex_main(
        uint vertexID [[vertex_id]],
        device const uchar *vertices [[buffer(0)]],
        constant BufferDescriptor &vertexDescriptor [[buffer(1)]],
        constant SilhouetteMaskUniforms &uniforms [[buffer(2)]]
    ) {
        float3 position = load_at<float3>(vertices, vertexDescriptor, vertexID);
        VertexOut out;
        out.position = uniforms.modelViewProjection * float4(position, 1.0);
        return out;
    }

    [[fragment]] float4 fragment_main(VertexOut in [[stage_in]]) {
        return float4(1.0);
    }

} // namespace SilhouetteMask
