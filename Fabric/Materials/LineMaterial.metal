//
//  LineMaterial.metal
//
//
//  Created by Anton Marini on 10/3/25.
//

#include <metal_stdlib>
using namespace metal;

typedef struct {
    float mode;          // 0 = True Geometry, 1 = Billboard, 2 = Perspective Min Pixel Width
    float pixelWidth;
    float minPixelWidth;
    float4 color;
    float colorBlend;    // 0 = ignore per-vertex color (flat `color` only), 1 = use per-vertex color outright
} LineUniforms;

typedef struct {
    float4 position [[position]];
    float2 uv;
    float3 normal;
    float4 color;
} LineVertexData;

// Screen-space perpendicular to the A->B direction, in NDC. Callers must check
// `degenerate` (A and B project to (near-)identical screen points) since the
// direction is meaningless in that case — this happens for hub/apex vertices
// whose core and neighbor coincide.
static float2 lineScreenPerpendicular(float4 clipA, float4 clipB, float2 viewportSize, thread bool &degenerate)
{
    const float2 ndcA = clipA.xy / clipA.w;
    const float2 ndcB = clipB.xy / clipB.w;
    const float2 screenDelta = (ndcB - ndcA) * viewportSize;
    const float screenLength = length(screenDelta);

    degenerate = screenLength < 1e-5;
    const float2 screenDir = degenerate ? float2(1.0, 0.0) : (screenDelta / screenLength);
    return float2(-screenDir.y, screenDir.x);
}

vertex LineVertexData lineVertex(Vertex in [[stage_in]],
                                  ushort amp_id [[amplification_id]],
                                  constant VertexUniforms *vertexUniforms [[buffer( VertexBufferVertexUniforms )]],
                                  constant LineUniforms &uniforms [[buffer( VertexBufferMaterialUniforms )]])
{
    LineVertexData out;

    const float4x4 mvp = vertexUniforms[amp_id].modelViewProjectionMatrix;
    const float2 viewportSize = vertexUniforms[amp_id].viewport.zw;
    const float4 bakedClip = mvp * float4(in.position, 1.0);

    if (uniforms.mode < 0.5 || viewportSize.x < 1.0 || viewportSize.y < 1.0)
    {
        // True Geometry: trust the CPU-tessellated position outright. Also the
        // safe fallback before the viewport uniform is valid (first frame).
        out.position = bakedClip;
    }
    else
    {
        const float4 clipCore = mvp * float4(in.custom1, 1.0);
        const float4 clipNeighbor = mvp * float4(in.custom2, 1.0);

        bool degenerate = false;
        const float2 screenPerp = lineScreenPerpendicular(clipCore, clipNeighbor, viewportSize, degenerate);

        float pixelHalfWidth = uniforms.pixelWidth * 0.5 * in.custom0.y;

        if (uniforms.mode > 1.5)
        {
            // Perspective Min Pixel Width: keep the true baked width unless it
            // would fall below the pixel floor, then clamp to the floor instead.
            const float2 bakedNdc = bakedClip.xy / bakedClip.w;
            const float2 coreNdc = clipCore.xy / clipCore.w;
            const float bakedPixelOffset = length((bakedNdc - coreNdc) * viewportSize * 0.5);
            pixelHalfWidth = max(bakedPixelOffset, uniforms.minPixelWidth * 0.5);
        }

        if (degenerate || in.custom0.x == 0.0)
        {
            // Centerline / hub vertices (side == 0, e.g. join fan apexes) have no
            // perpendicular offset regardless of mode — ride along at the core point.
            out.position = clipCore;
        }
        else
        {
            const float2 ndcOffset = screenPerp * (pixelHalfWidth / viewportSize) * 2.0 * in.custom0.x;
            out.position = clipCore + float4(ndcOffset * clipCore.w, 0.0, 0.0);
        }
    }

    out.uv = in.texcoord;
    out.normal = in.normal;
    out.color = in.color;
    return out;
}

fragment half4 lineFragment(LineVertexData in [[stage_in]],
                             constant LineUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]])
{
    const float4 color = mix(uniforms.color, in.color, uniforms.colorBlend);
    return half4(color);
}
