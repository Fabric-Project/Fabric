using namespace metal;

#include <metal_stdlib>

typedef struct {
    float amount; // slider, 0.0, 5.0, 0.0, Amount
} PostUniforms;

struct GaussianPassUniforms {
    float2 direction;
    float amountScale;
    float _padding;
};

fragment half4 postFragment(VertexData in [[stage_in]],
                            constant PostUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
                            texture2d<half, access::sample> renderTex [[texture(FragmentTextureCustom0)]],
                            texture2d<half, access::sample> renderTex2 [[texture(FragmentTextureCustom1)]],
                            constant GaussianPassUniforms &passUniforms [[buffer(FragmentBufferCustom0)]])
{
    constexpr sampler linearSampler(coord::normalized,
                                    address::clamp_to_edge,
                                    min_filter::linear,
                                    mag_filter::linear);


    
    const float2 texelSize = 1.0 / float2(renderTex.get_width(), renderTex.get_height());
    const float2 blurStep = texelSize * passUniforms.direction * (uniforms.amount * passUniforms.amountScale);

    const float2 uv = in.texcoord;

    half4 mask = renderTex2.sample(linearSampler, in.texcoord);

    half4 sample0 = renderTex.sample(linearSampler, uv);
    half4 sample1 = renderTex.sample(linearSampler, uv - blurStep * mask.r);
    half4 sample2 = renderTex.sample(linearSampler, uv + blurStep * mask.r);

    return (sample0 + sample1 + sample2) / 3.0h;
}
