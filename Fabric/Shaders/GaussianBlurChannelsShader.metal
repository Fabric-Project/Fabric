using namespace metal;

#include <metal_stdlib>
#include "FabricImageTextureTransform.metal"

typedef struct {
    float redAmount; // slider, 0.0, 50.0, 0.0, Red Amount
    float greenAmount; // slider, 0.0, 50.0, 0.0, Green Amount
    float blueAmount; // slider, 0.0, 50.0, 0.0, Blue Amount
} PostUniforms;

struct GaussianPassUniforms {
    float2 direction;
    float amountScale;
    float _padding;
};

static inline half4 weightedSamples(texture2d<half, access::sample> renderTex,
                                    sampler linearSampler,
                                    float4x4 textureTransform,
                                    float2 uv,
                                    float2 blurStep)
{
    half4 sample0 = renderTex.sample(linearSampler, fabricTextureCoordinate(textureTransform, uv));
    half4 sample1 = renderTex.sample(linearSampler, fabricTextureCoordinate(textureTransform, uv - blurStep * 0.5f));
    half4 sample2 = renderTex.sample(linearSampler, fabricTextureCoordinate(textureTransform, uv + blurStep * 0.5f));
    half4 sample3 = renderTex.sample(linearSampler, fabricTextureCoordinate(textureTransform, uv - blurStep));
    half4 sample4 = renderTex.sample(linearSampler, fabricTextureCoordinate(textureTransform, uv + blurStep));

    return sample0 * 0.40262h +
           sample1 * 0.24420h +
           sample2 * 0.24420h +
           sample3 * 0.05449h +
           sample4 * 0.05449h;
}

fragment half4 postFragment(VertexData in [[stage_in]],
                            constant PostUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
                            texture2d<half, access::sample> renderTex [[texture(FragmentTextureCustom0)]],
                            texture2d<half, access::sample> originalTex [[texture(FragmentTextureCustom1)]],
                            constant GaussianPassUniforms &passUniforms [[buffer(FragmentBufferCustom0)]],
                            constant float4x4 *textureTransforms [[buffer(FragmentBufferCustom10)]])
{
    constexpr sampler linearSampler(coord::normalized,
                                    address::clamp_to_edge,
                                    min_filter::linear,
                                    mag_filter::linear);

    const float2 textureSize = float2(renderTex.get_width(), renderTex.get_height());
    const float2 texelSize = 1.0f / fabricPresentationSize(textureTransforms[0], textureSize);
    const float2 scaledDirection = texelSize * passUniforms.direction * passUniforms.amountScale;
    const float2 uv = in.texcoord;
    half4 original = originalTex.sample(linearSampler, fabricTextureCoordinate(textureTransforms[1], uv));

    half red = uniforms.redAmount <= 0.0001f
        ? original.r
        : weightedSamples(renderTex, linearSampler, textureTransforms[0], uv, scaledDirection * uniforms.redAmount).r;
    half green = uniforms.greenAmount <= 0.0001f
        ? original.g
        : weightedSamples(renderTex, linearSampler, textureTransforms[0], uv, scaledDirection * uniforms.greenAmount).g;
    half blue = uniforms.blueAmount <= 0.0001f
        ? original.b
        : weightedSamples(renderTex, linearSampler, textureTransforms[0], uv, scaledDirection * uniforms.blueAmount).b;

    return half4(red, green, blue, original.a);
}
