using namespace metal;

#include <metal_stdlib>
#include "../lygia/math/radians.msl"

typedef struct {
    float amount; // slider, 0.0, 5.0, 0.0, Amount
    float angle; // slider, 0.0, 360.0, 0.0, Angle
} PostUniforms;

struct MotionPassUniforms {
    float amountScale;
};

fragment half4 postFragment(VertexData in [[stage_in]],
                            constant PostUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
                            texture2d<half, access::sample> renderTex [[texture(FragmentTextureCustom0)]],
                            constant MotionPassUniforms &passUniforms [[buffer(FragmentBufferCustom0)]])
{
    constexpr sampler linearSampler(coord::normalized,
                                    address::clamp_to_edge,
                                    min_filter::linear,
                                    mag_filter::linear);

    const float2 texelSize = 1.0 / float2(renderTex.get_width(), renderTex.get_height());

    const float theta = radians(uniforms.angle);
    const float2 direction = float2(cos(theta), sin(theta));

    const float scaledAmount = uniforms.amount * passUniforms.amountScale;

    const float2 step1 = direction * texelSize * (scaledAmount * 1.0);
    const float2 step2 = direction * texelSize * (scaledAmount * 3.0);
    const float2 step3 = direction * texelSize * (scaledAmount * 6.0);
    const float2 step4 = direction * texelSize * (scaledAmount * 9.0);

    const float2 uv = in.texcoord;

    half4 sample0 = renderTex.sample(linearSampler, uv);
    half4 sample1 = renderTex.sample(linearSampler, uv + step1);
    half4 sample2 = renderTex.sample(linearSampler, uv + step2);
    half4 sample3 = renderTex.sample(linearSampler, uv + step3);
    half4 sample4 = renderTex.sample(linearSampler, uv + step4);
    half4 sample5 = renderTex.sample(linearSampler, uv - step1);
    half4 sample6 = renderTex.sample(linearSampler, uv - step2);
    half4 sample7 = renderTex.sample(linearSampler, uv - step3);
    half4 sample8 = renderTex.sample(linearSampler, uv - step4);

    return (sample0 + sample1 + sample2 + sample3 + sample4 + sample5 + sample6 + sample7 + sample8) / 9.0h;
}
