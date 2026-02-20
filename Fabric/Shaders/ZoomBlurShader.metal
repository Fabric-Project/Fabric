using namespace metal;

#include <metal_stdlib>

typedef struct {
    float amount; // slider, 0.0, 50.0, 0.0, Amount
    float2 origin; // xypad, -2.0, 2.0, 0.0, Origin
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

    const float2 uv = in.texcoord;

    const float2 origin = uniforms.origin + 0.5;//float2(uniforms.originX + 0.5, uniforms.originY + 0.5);

    const float2 destination = uv - origin;

    const float2 texelSize = 1.0 / float2(renderTex.get_width(), renderTex.get_height());
//    const float2 off = (destination * (amount + 1.0)) / (texSize * (amount + 1.0) );//    const float2 off = 1.0;//' / texSize;

    const float scaledAmount = uniforms.amount * passUniforms.amountScale * length(texelSize);

    const float2 step1 = destination * (scaledAmount / 8.0) ;
    const float2 step2 = destination * (scaledAmount / 4.0) ;
    const float2 step3 = destination * (scaledAmount / 2.0) ;
    const float2 step4 = destination * (scaledAmount / 1.0) ;

    half4 sample0 = renderTex.sample(linearSampler, uv);
    half4 sample1 = renderTex.sample(linearSampler, destination + step1 + origin);
    half4 sample2 = renderTex.sample(linearSampler, destination - step1 + origin);
    half4 sample3 = renderTex.sample(linearSampler, destination + step2 + origin);
    half4 sample4 = renderTex.sample(linearSampler, destination - step2 + origin);
    half4 sample5 = renderTex.sample(linearSampler, destination + step3 + origin);
    half4 sample6 = renderTex.sample(linearSampler, destination - step3 + origin);
    half4 sample7 = renderTex.sample(linearSampler, destination + step4 + origin);
    half4 sample8 = renderTex.sample(linearSampler, destination - step4 + origin);

    
//    half4 sample0 = renderTex.sample(linearSampler, destination + off + origin);
//    half4 sample1 = renderTex.sample(linearSampler, destination + ( off * (2.0 * scaledAmount) ) + origin);
//    half4 sample2 = renderTex.sample(linearSampler, destination - ( off * (2.0 * scaledAmount) ) + origin);
//    half4 sample3 = renderTex.sample(linearSampler, destination + ( off * (3.0 * scaledAmount) ) + origin);
//    half4 sample4 = renderTex.sample(linearSampler, destination - ( off * (3.0 * scaledAmount) ) + origin);
//    half4 sample5 = renderTex.sample(linearSampler, destination + ( off * (4.0 * scaledAmount) ) + origin);
//    half4 sample6 = renderTex.sample(linearSampler, destination - ( off * (4.0 * scaledAmount) ) + origin);
//    half4 sample7 = renderTex.sample(linearSampler, destination + ( off * (5.0 * scaledAmount) ) + origin);
//    half4 sample8 = renderTex.sample(linearSampler, destination - ( off * (5.0 * scaledAmount) ) + origin);

//    return (sample0 + sample1 + sample2 + sample3 + sample4 + sample5 + sample6 + sample7 + sample8) / 9.0h;
    return (sample0 * 0.39894 + sample1 * 0.24197 + sample2 * 0.24197 + sample3 * 0.05399 + sample4 * 0.05399 + sample5 * 0.00443 + sample6 * 0.00443 + sample7 * 0.00013+ sample8 * 0.00013);
}
