using namespace metal;

#include <metal_stdlib>

typedef struct {
    float amount; // slider, 0.0, 5.0, 0.0, Amount
    float originX; // slider, -2.0, 2.0, 0.0, Origin X
    float originY; // slider, -2.0, 2.0, 0.0, Origin Y
} PostUniforms;

struct ZoomPassUniforms {
    float amountScale;
};

fragment half4 postFragment(VertexData in [[stage_in]],
                            constant PostUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
                            texture2d<half, access::sample> renderTex [[texture(FragmentTextureCustom0)]],
                            constant ZoomPassUniforms &passUniforms [[buffer(FragmentBufferCustom0)]])
{
    constexpr sampler linearSampler(coord::normalized,
                                    address::clamp_to_edge,
                                    min_filter::linear,
                                    mag_filter::linear);

    const float amount = uniforms.amount * passUniforms.amountScale;
    const float2 uv = in.texcoord;

    const float2 origin = float2(uniforms.originX + 0.5, uniforms.originY + 0.5);

    const float2 destination = uv - origin;

    const float2 texSize = float2(renderTex.get_width(), renderTex.get_height());
    const float2 off = (destination * amount + 1.0) / (texSize * amount + 1.0);

    const float scaleBase = amount * 0.2;

    half4 sample0 = renderTex.sample(linearSampler, destination + origin);
    half4 sample1 = renderTex.sample(linearSampler, destination + off * (3.0 * scaleBase) + origin);
    half4 sample2 = renderTex.sample(linearSampler, destination - off * (3.0 * scaleBase) + origin);
    half4 sample3 = renderTex.sample(linearSampler, destination + off * (6.0 * scaleBase) + origin);
    half4 sample4 = renderTex.sample(linearSampler, destination - off * (6.0 * scaleBase) + origin);
    half4 sample5 = renderTex.sample(linearSampler, destination + off * (12.0 * scaleBase) + origin);
    half4 sample6 = renderTex.sample(linearSampler, destination - off * (12.0 * scaleBase) + origin);
    half4 sample7 = renderTex.sample(linearSampler, destination + off * (18.0 * scaleBase) + origin);
    half4 sample8 = renderTex.sample(linearSampler, destination - off * (18.0 * scaleBase) + origin);

    return (sample0 + sample1 + sample2 + sample3 + sample4 + sample5 + sample6 + sample7 + sample8) / 9.0h;
}
