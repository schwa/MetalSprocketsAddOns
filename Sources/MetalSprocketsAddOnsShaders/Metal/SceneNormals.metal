#include "MetalSprocketsAddOnsShaders.h"

using namespace metal;

// Writes world-space shading normals for the shadow passes (see ShadowContext.normalTexture).
namespace SceneNormals {

    struct VertexIn {
        float3 position [[attribute(0)]];
        float3 normal [[attribute(1)]];
    };

    struct VertexOut {
        float4 position [[position]];
        float3 worldNormal;
    };

    [[vertex]] VertexOut vertex_main(
        const VertexIn in [[stage_in]],
        constant float4x4 &modelViewProjectionMatrix [[buffer(1)]],
        constant float3x3 &normalMatrix [[buffer(2)]]
    ) {
        return { modelViewProjectionMatrix * float4(in.position, 1.0), normalMatrix * in.normal };
    }

    [[fragment]] float4 fragment_main(VertexOut in [[stage_in]]) {
        return float4(normalize(in.worldNormal), 1.0);
    }

} // namespace SceneNormals
