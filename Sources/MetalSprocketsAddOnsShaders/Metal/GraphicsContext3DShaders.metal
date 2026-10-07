#include "MetalSprocketsAddOnsShaders.h"

using namespace metal;

namespace GraphicsContext3D {

    // MARK: Types

    struct VertexOut {
        float4 position [[position]];
        float4 color;
    };

    using MeshType = mesh<VertexOut, void, 256, 512, topology::triangle>;

    struct ObjectPayload {
        uint joinIndex;
    };

    // MARK: Helper functions

    int segmentCountForRadius(float radius) {
        if (radius < 2.0) return 3;
        if (radius < 5.0) return 4;
        if (radius < 10.0) return 6;
        if (radius < 20.0) return 8;
        if (radius < 40.0) return 12;
        return 16;
    }

    // Points with w below this are behind (or on) the camera plane. Segments are clipped to it
    // before the perspective divide; the rasterizer's depth clip then trims at the real near plane.
    constant float minimumW = 1e-4;

    // Callers must clip first so clipPos.w >= minimumW.
    float2 toScreen(float4 clipPos, float2 viewport) {
        float2 ndc = clipPos.xy / clipPos.w;
        return (ndc * 0.5 + 0.5) * viewport;
    }

    // Clips the clip-space segment a-b to w >= minimumW. Returns false if the whole segment is behind the camera.
    bool clipSegment(thread float4& a, thread float4& b) {
        bool aVisible = a.w >= minimumW;
        bool bVisible = b.w >= minimumW;
        if (!aVisible && !bVisible) return false;
        if (aVisible && bVisible) return true;
        float4 crossing = mix(a, b, (minimumW - a.w) / (b.w - a.w));
        if (aVisible) {
            b = crossing;
        } else {
            a = crossing;
        }
        return true;
    }

    float3 toClip(float2 screenPos, float depth, float w, float2 viewport) {
        float2 ndc = (screenPos / viewport) * 2.0 - 1.0;
        return float3(ndc, depth);
    }

    // MARK: Object Shader

    [[object, max_total_threads_per_threadgroup(1)]]
    void lineJoinObjectShader(
        uint objectID [[thread_position_in_grid]],
        object_data ObjectPayload& payload [[payload]],
        mesh_grid_properties mgp
    ) {
        payload.joinIndex = objectID;
        mgp.set_threadgroups_per_grid(uint3(1, 1, 1));
    }

    // MARK: Mesh Shader

    [[mesh, max_total_threads_per_threadgroup(1)]]
    void lineJoinMeshShader(
        MeshType mesh_out,
        const device LineJoinGPUData* joinData [[buffer(0)]],
        const device LineJoinUniforms& uniforms [[buffer(1)]],
        object_data const ObjectPayload& payload [[payload]]
    ) {
        uint joinIndex = payload.joinIndex;
        LineJoinGPUData data = joinData[joinIndex];

        float radius = data.lineWidth / 2.0;

        uint vertexCount = 0;
        uint primitiveCount = 0;

        float4 prevClip = uniforms.viewProjection * float4(data.prevPoint, 1.0);
        float4 joinClip = uniforms.viewProjection * float4(data.joinPoint, 1.0);
        float4 nextClip = uniforms.viewProjection * float4(data.nextPoint, 1.0);

        // Clip each half-segment against the camera plane before projecting, so points
        // behind the camera are never mirrored across the screen.
        float4 segmentAStart = prevClip;
        float4 segmentAEnd = joinClip;
        bool hasSegmentA = data.isStartCap == 0 && clipSegment(segmentAStart, segmentAEnd);

        float4 segmentBStart = joinClip;
        float4 segmentBEnd = nextClip;
        bool hasSegmentB = data.isEndCap == 0 && clipSegment(segmentBStart, segmentBEnd);

        // Half-segment A: prevPoint to joinPoint
        if (hasSegmentA) {
            float2 startScreen = toScreen(segmentAStart, uniforms.viewport);
            float2 endScreen = toScreen(segmentAEnd, uniforms.viewport);
            float startDepth = segmentAStart.z / segmentAStart.w;
            float endDepth = segmentAEnd.z / segmentAEnd.w;

            float2 direction = normalize(endScreen - startScreen);
            float2 perpendicular = float2(-direction.y, direction.x);

            float2 p0 = startScreen - perpendicular * radius;
            float2 p1 = startScreen + perpendicular * radius;
            float2 p2 = endScreen + perpendicular * radius;
            float2 p3 = endScreen - perpendicular * radius;

            mesh_out.set_vertex(vertexCount + 0, VertexOut{float4(toClip(p0, startDepth, 1.0, uniforms.viewport), 1.0), data.color});
            mesh_out.set_vertex(vertexCount + 1, VertexOut{float4(toClip(p1, startDepth, 1.0, uniforms.viewport), 1.0), data.color});
            mesh_out.set_vertex(vertexCount + 2, VertexOut{float4(toClip(p2, endDepth, 1.0, uniforms.viewport), 1.0), data.color});
            mesh_out.set_vertex(vertexCount + 3, VertexOut{float4(toClip(p3, endDepth, 1.0, uniforms.viewport), 1.0), data.color});

            mesh_out.set_index(primitiveCount * 3 + 0, vertexCount + 0);
            mesh_out.set_index(primitiveCount * 3 + 1, vertexCount + 1);
            mesh_out.set_index(primitiveCount * 3 + 2, vertexCount + 2);
            primitiveCount++;

            mesh_out.set_index(primitiveCount * 3 + 0, vertexCount + 0);
            mesh_out.set_index(primitiveCount * 3 + 1, vertexCount + 2);
            mesh_out.set_index(primitiveCount * 3 + 2, vertexCount + 3);
            primitiveCount++;

            vertexCount += 4;
        }

        // Half-segment B: joinPoint to nextPoint
        if (hasSegmentB) {
            float2 startScreen = toScreen(segmentBStart, uniforms.viewport);
            float2 endScreen = toScreen(segmentBEnd, uniforms.viewport);
            float startDepth = segmentBStart.z / segmentBStart.w;
            float endDepth = segmentBEnd.z / segmentBEnd.w;

            float2 direction = normalize(endScreen - startScreen);
            float2 perpendicular = float2(-direction.y, direction.x);

            float2 p0 = startScreen - perpendicular * radius;
            float2 p1 = startScreen + perpendicular * radius;
            float2 p2 = endScreen + perpendicular * radius;
            float2 p3 = endScreen - perpendicular * radius;

            mesh_out.set_vertex(vertexCount + 0, VertexOut{float4(toClip(p0, startDepth, 1.0, uniforms.viewport), 1.0), data.color});
            mesh_out.set_vertex(vertexCount + 1, VertexOut{float4(toClip(p1, startDepth, 1.0, uniforms.viewport), 1.0), data.color});
            mesh_out.set_vertex(vertexCount + 2, VertexOut{float4(toClip(p2, endDepth, 1.0, uniforms.viewport), 1.0), data.color});
            mesh_out.set_vertex(vertexCount + 3, VertexOut{float4(toClip(p3, endDepth, 1.0, uniforms.viewport), 1.0), data.color});

            mesh_out.set_index(primitiveCount * 3 + 0, vertexCount + 0);
            mesh_out.set_index(primitiveCount * 3 + 1, vertexCount + 1);
            mesh_out.set_index(primitiveCount * 3 + 2, vertexCount + 2);
            primitiveCount++;

            mesh_out.set_index(primitiveCount * 3 + 0, vertexCount + 0);
            mesh_out.set_index(primitiveCount * 3 + 1, vertexCount + 2);
            mesh_out.set_index(primitiveCount * 3 + 2, vertexCount + 3);
            primitiveCount++;

            vertexCount += 4;
        }

        // Joins and caps sit on the join point, so skip them when it is behind the camera.
        if (joinClip.w < minimumW) {
            mesh_out.set_primitive_count(primitiveCount);
            return;
        }

        // When the join point is visible, the clipped segment ends give the on-screen directions.
        float2 joinScreen = toScreen(joinClip, uniforms.viewport);
        float2 prevScreen = hasSegmentA ? toScreen(segmentAStart, uniforms.viewport) : joinScreen;
        float2 nextScreen = hasSegmentB ? toScreen(segmentBEnd, uniforms.viewport) : joinScreen;
        float joinDepth = joinClip.z / joinClip.w;

        // Join at center point
        if (data.isStartCap == 0 && data.isEndCap == 0) {
            float2 dirPrev = normalize(joinScreen - prevScreen);
            float2 dirNext = normalize(nextScreen - joinScreen);

            float crossProd = dirPrev.x * dirNext.y - dirPrev.y * dirNext.x;

            // Choose perpendicular direction based on turn direction to ensure it points outside
            // Left turn (cross > 0): rotate clockwise, Right turn (cross < 0): rotate counter-clockwise
            float2 perpPrev = crossProd > 0 ? float2(dirPrev.y, -dirPrev.x) : float2(-dirPrev.y, dirPrev.x);
            float2 perpNext = crossProd > 0 ? float2(dirNext.y, -dirNext.x) : float2(-dirNext.y, dirNext.x);

            if (data.joinStyle == 1) {  // Round join
                int segments = segmentCountForRadius(radius);
                segments = min(segments, 16);  // Cap for vertex budget

                float startAngle = atan2(perpPrev.y, perpPrev.x);
                float endAngle = atan2(perpNext.y, perpNext.x);
                float angleDelta = endAngle - startAngle;

                if (crossProd > 0) {
                    if (angleDelta < 0) angleDelta += 2.0 * M_PI_F;
                } else {
                    if (angleDelta > 0) angleDelta -= 2.0 * M_PI_F;
                }

                uint centerVertex = vertexCount++;
                mesh_out.set_vertex(centerVertex, VertexOut{float4(toClip(joinScreen, joinDepth, joinClip.w, uniforms.viewport), 1.0), data.color});

                for (int i = 0; i <= segments; i++) {
                    float t = float(i) / float(segments);
                    float angle = startAngle + angleDelta * t;
                    float2 offset = float2(cos(angle), sin(angle)) * radius;
                    float2 p = joinScreen + offset;

                    mesh_out.set_vertex(vertexCount, VertexOut{float4(toClip(p, joinDepth, joinClip.w, uniforms.viewport), 1.0), data.color});

                    if (i > 0) {
                        mesh_out.set_index(primitiveCount * 3 + 0, centerVertex);
                        mesh_out.set_index(primitiveCount * 3 + 1, vertexCount - 1);
                        mesh_out.set_index(primitiveCount * 3 + 2, vertexCount);
                        primitiveCount++;
                    }
                    vertexCount++;
                }
            } else if (data.joinStyle == 0) {  // Miter
                float2 prevOuter = joinScreen + perpPrev * radius;
                float2 nextOuter = joinScreen + perpNext * radius;

                // Find intersection of two offset lines:
                // Line 1: prevOuter + t * dirPrev
                // Line 2: nextOuter + s * dirNext
                float denom = dirPrev.x * dirNext.y - dirPrev.y * dirNext.x;

                bool useBevel = false;
                float2 miterPoint;

                if (abs(denom) < 1e-6) {
                    // Lines are parallel, use bevel
                    useBevel = true;
                } else {
                    float2 diff = nextOuter - prevOuter;
                    float t = (diff.x * dirNext.y - diff.y * dirNext.x) / denom;
                    miterPoint = prevOuter + t * dirPrev;

                    // Check miter limit
                    float miterDist = distance(miterPoint, joinScreen);
                    float miterRatio = miterDist / radius;

                    if (miterRatio > data.miterLimit) {
                        useBevel = true;
                    }
                }

                if (useBevel) {
                    // Bevel: simple triangle from center to both outer points
                    mesh_out.set_vertex(vertexCount + 0, VertexOut{float4(toClip(joinScreen, joinDepth, joinClip.w, uniforms.viewport), 1.0), data.color});
                    mesh_out.set_vertex(vertexCount + 1, VertexOut{float4(toClip(prevOuter, joinDepth, joinClip.w, uniforms.viewport), 1.0), data.color});
                    mesh_out.set_vertex(vertexCount + 2, VertexOut{float4(toClip(nextOuter, joinDepth, joinClip.w, uniforms.viewport), 1.0), data.color});

                    mesh_out.set_index(primitiveCount * 3 + 0, vertexCount + 0);
                    mesh_out.set_index(primitiveCount * 3 + 1, vertexCount + 1);
                    mesh_out.set_index(primitiveCount * 3 + 2, vertexCount + 2);
                    primitiveCount++;
                    vertexCount += 3;
                } else {
                    // Miter: two triangles using the miter point
                    mesh_out.set_vertex(vertexCount + 0, VertexOut{float4(toClip(joinScreen, joinDepth, joinClip.w, uniforms.viewport), 1.0), data.color});
                    mesh_out.set_vertex(vertexCount + 1, VertexOut{float4(toClip(prevOuter, joinDepth, joinClip.w, uniforms.viewport), 1.0), data.color});
                    mesh_out.set_vertex(vertexCount + 2, VertexOut{float4(toClip(miterPoint, joinDepth, joinClip.w, uniforms.viewport), 1.0), data.color});
                    mesh_out.set_vertex(vertexCount + 3, VertexOut{float4(toClip(nextOuter, joinDepth, joinClip.w, uniforms.viewport), 1.0), data.color});

                    mesh_out.set_index(primitiveCount * 3 + 0, vertexCount + 0);
                    mesh_out.set_index(primitiveCount * 3 + 1, vertexCount + 1);
                    mesh_out.set_index(primitiveCount * 3 + 2, vertexCount + 2);
                    primitiveCount++;

                    mesh_out.set_index(primitiveCount * 3 + 0, vertexCount + 0);
                    mesh_out.set_index(primitiveCount * 3 + 1, vertexCount + 2);
                    mesh_out.set_index(primitiveCount * 3 + 2, vertexCount + 3);
                    primitiveCount++;

                    vertexCount += 4;
                }
            } else {  // Bevel (joinStyle == 2)
                float2 prevOuter = joinScreen + perpPrev * radius;
                float2 nextOuter = joinScreen + perpNext * radius;

                mesh_out.set_vertex(vertexCount + 0, VertexOut{float4(toClip(joinScreen, joinDepth, joinClip.w, uniforms.viewport), 1.0), data.color});
                mesh_out.set_vertex(vertexCount + 1, VertexOut{float4(toClip(prevOuter, joinDepth, joinClip.w, uniforms.viewport), 1.0), data.color});
                mesh_out.set_vertex(vertexCount + 2, VertexOut{float4(toClip(nextOuter, joinDepth, joinClip.w, uniforms.viewport), 1.0), data.color});

                mesh_out.set_index(primitiveCount * 3 + 0, vertexCount + 0);
                mesh_out.set_index(primitiveCount * 3 + 1, vertexCount + 1);
                mesh_out.set_index(primitiveCount * 3 + 2, vertexCount + 2);
                primitiveCount++;
                vertexCount += 3;
            }
        }

        // Start cap
        if (data.isStartCap == 1) {
            float2 dir = normalize(joinScreen - nextScreen);
            float2 perp = float2(-dir.y, dir.x);

            if (data.capStyle == 2) {  // Round cap
                int segments = segmentCountForRadius(radius);
                segments = min(segments, 16);

                float dirAngle = atan2(dir.y, dir.x);
                float startAngle = dirAngle - M_PI_F / 2.0;

                uint centerVertex = vertexCount++;
                mesh_out.set_vertex(centerVertex, VertexOut{float4(toClip(joinScreen, joinDepth, joinClip.w, uniforms.viewport), 1.0), data.color});

                for (int i = 0; i <= segments; i++) {
                    float t = float(i) / float(segments);
                    float angle = startAngle + M_PI_F * t;
                    float2 offset = float2(cos(angle), sin(angle)) * radius;
                    float2 p = joinScreen + offset;

                    mesh_out.set_vertex(vertexCount, VertexOut{float4(toClip(p, joinDepth, joinClip.w, uniforms.viewport), 1.0), data.color});

                    if (i > 0) {
                        mesh_out.set_index(primitiveCount * 3 + 0, centerVertex);
                        mesh_out.set_index(primitiveCount * 3 + 1, vertexCount - 1);
                        mesh_out.set_index(primitiveCount * 3 + 2, vertexCount);
                        primitiveCount++;
                    }
                    vertexCount++;
                }
            } else if (data.capStyle == 3) {  // Square cap
                float2 p0 = joinScreen - perp * radius + dir * radius;
                float2 p1 = joinScreen + perp * radius + dir * radius;
                float2 p2 = joinScreen + perp * radius;
                float2 p3 = joinScreen - perp * radius;

                mesh_out.set_vertex(vertexCount + 0, VertexOut{float4(toClip(p0, joinDepth, joinClip.w, uniforms.viewport), 1.0), data.color});
                mesh_out.set_vertex(vertexCount + 1, VertexOut{float4(toClip(p1, joinDepth, joinClip.w, uniforms.viewport), 1.0), data.color});
                mesh_out.set_vertex(vertexCount + 2, VertexOut{float4(toClip(p2, joinDepth, joinClip.w, uniforms.viewport), 1.0), data.color});
                mesh_out.set_vertex(vertexCount + 3, VertexOut{float4(toClip(p3, joinDepth, joinClip.w, uniforms.viewport), 1.0), data.color});

                mesh_out.set_index(primitiveCount * 3 + 0, vertexCount + 0);
                mesh_out.set_index(primitiveCount * 3 + 1, vertexCount + 1);
                mesh_out.set_index(primitiveCount * 3 + 2, vertexCount + 2);
                primitiveCount++;

                mesh_out.set_index(primitiveCount * 3 + 0, vertexCount + 0);
                mesh_out.set_index(primitiveCount * 3 + 1, vertexCount + 2);
                mesh_out.set_index(primitiveCount * 3 + 2, vertexCount + 3);
                primitiveCount++;
                vertexCount += 4;
            }
        }

        // End cap
        if (data.isEndCap == 1) {
            float2 dir = normalize(joinScreen - prevScreen);
            float2 perp = float2(-dir.y, dir.x);

            if (data.capStyle == 2) {  // Round cap
                int segments = segmentCountForRadius(radius);
                segments = min(segments, 16);

                float dirAngle = atan2(dir.y, dir.x);
                float startAngle = dirAngle - M_PI_F / 2.0;

                uint centerVertex = vertexCount++;
                mesh_out.set_vertex(centerVertex, VertexOut{float4(toClip(joinScreen, joinDepth, joinClip.w, uniforms.viewport), 1.0), data.color});

                for (int i = 0; i <= segments; i++) {
                    float t = float(i) / float(segments);
                    float angle = startAngle + M_PI_F * t;
                    float2 offset = float2(cos(angle), sin(angle)) * radius;
                    float2 p = joinScreen + offset;

                    mesh_out.set_vertex(vertexCount, VertexOut{float4(toClip(p, joinDepth, joinClip.w, uniforms.viewport), 1.0), data.color});

                    if (i > 0) {
                        mesh_out.set_index(primitiveCount * 3 + 0, centerVertex);
                        mesh_out.set_index(primitiveCount * 3 + 1, vertexCount - 1);
                        mesh_out.set_index(primitiveCount * 3 + 2, vertexCount);
                        primitiveCount++;
                    }
                    vertexCount++;
                }
            } else if (data.capStyle == 3) {  // Square cap
                float2 p0 = joinScreen - perp * radius;
                float2 p1 = joinScreen + perp * radius;
                float2 p2 = joinScreen + perp * radius + dir * radius;
                float2 p3 = joinScreen - perp * radius + dir * radius;

                mesh_out.set_vertex(vertexCount + 0, VertexOut{float4(toClip(p0, joinDepth, joinClip.w, uniforms.viewport), 1.0), data.color});
                mesh_out.set_vertex(vertexCount + 1, VertexOut{float4(toClip(p1, joinDepth, joinClip.w, uniforms.viewport), 1.0), data.color});
                mesh_out.set_vertex(vertexCount + 2, VertexOut{float4(toClip(p2, joinDepth, joinClip.w, uniforms.viewport), 1.0), data.color});
                mesh_out.set_vertex(vertexCount + 3, VertexOut{float4(toClip(p3, joinDepth, joinClip.w, uniforms.viewport), 1.0), data.color});

                mesh_out.set_index(primitiveCount * 3 + 0, vertexCount + 0);
                mesh_out.set_index(primitiveCount * 3 + 1, vertexCount + 1);
                mesh_out.set_index(primitiveCount * 3 + 2, vertexCount + 2);
                primitiveCount++;

                mesh_out.set_index(primitiveCount * 3 + 0, vertexCount + 0);
                mesh_out.set_index(primitiveCount * 3 + 1, vertexCount + 2);
                mesh_out.set_index(primitiveCount * 3 + 2, vertexCount + 3);
                primitiveCount++;
                vertexCount += 4;
            }
        }

        mesh_out.set_primitive_count(primitiveCount);
    }

    // MARK: Vertex Shader

    [[vertex]] VertexOut vertexShader(
        const device GraphicsContext3DVertex* vertices [[buffer(0)]],
        const device LineJoinUniforms& uniforms [[buffer(1)]],
        uint vertexID [[vertex_id]]
    ) {
        GraphicsContext3DVertex in = vertices[vertexID];
        VertexOut out;
        // Full clip-space position, so the rasterizer clips fills against the near plane.
        out.position = uniforms.viewProjection * float4(in.position, 1.0);
        out.color = in.color;
        return out;
    }

    // MARK: Fragment Shader

    [[fragment]] float4 fragmentShader(
        VertexOut in [[stage_in]]
    ) {
        return in.color;
    }
};
