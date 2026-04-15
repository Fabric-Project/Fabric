#include <metal_stdlib>
using namespace metal;

struct MSDFGlyphInstance
{
    float4 screenRect;
    float4 atlasUVRect;
    float4 color;
};

struct MSDFUniforms
{
    float2 viewportSize;
    float distanceRange;
    float padding;
};

struct VertexOut
{
    float4 position [[position]];
    float2 uv;
    float4 color;
};

inline float msdfMedian3(float r, float g, float b)
{
    return max(min(r, g), min(max(r, g), b));
}

vertex VertexOut msdf_node_vertex(
    uint vertexId [[vertex_id]],
    uint instanceId [[instance_id]],
    const device MSDFGlyphInstance *instances [[buffer(0)]],
    constant MSDFUniforms &uniforms [[buffer(1)]]
)
{
    float2 quad[6];
    quad[0] = float2(0.0, 0.0);
    quad[1] = float2(1.0, 0.0);
    quad[2] = float2(0.0, 1.0);
    quad[3] = float2(1.0, 0.0);
    quad[4] = float2(1.0, 1.0);
    quad[5] = float2(0.0, 1.0);

    MSDFGlyphInstance glyphInstance = instances[instanceId];
    float2 quadPosition = quad[vertexId];
    float2 pixelPosition = float2(
        mix(glyphInstance.screenRect.x, glyphInstance.screenRect.z, quadPosition.x),
        mix(glyphInstance.screenRect.y, glyphInstance.screenRect.w, quadPosition.y)
    );

    float2 ndc = float2(
        (pixelPosition.x / uniforms.viewportSize.x) * 2.0 - 1.0,
        1.0 - (pixelPosition.y / uniforms.viewportSize.y) * 2.0
    );

    VertexOut outVertex;
    outVertex.position = float4(ndc, 0.0, 1.0);
    outVertex.uv = float2(
        mix(glyphInstance.atlasUVRect.x, glyphInstance.atlasUVRect.z, quadPosition.x),
        mix(glyphInstance.atlasUVRect.y, glyphInstance.atlasUVRect.w, quadPosition.y)
    );
    outVertex.color = glyphInstance.color;
    return outVertex;
}

fragment float4 msdf_node_fragment(
    VertexOut inVertex [[stage_in]],
    texture2d<float, access::sample> atlasTexture [[texture(0)]],
    sampler atlasSampler [[sampler(0)]]
)
{
    float3 msdfSample = atlasTexture.sample(atlasSampler, inVertex.uv).rgb;
    float signedDistance = msdfMedian3(msdfSample.r, msdfSample.g, msdfSample.b) - 0.5;
    float smoothing = abs(dfdx(signedDistance)) + abs(dfdy(signedDistance));
    float edgeWidth = max(smoothing, 0.0001);
    float alpha = smoothstep(-edgeWidth, edgeWidth, signedDistance);
    return float4(inVertex.color.rgb, inVertex.color.a * alpha);
}
