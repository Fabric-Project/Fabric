//
//  Halation.metal
//  Fabric
//
// description: Adds tinted blurred highlights back into a clean source image

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"
#include "../../lygia/color/blend.msl"

typedef struct {
    float4 tint; // color, 1.0, 0.35, 0.12, 1.0, Tint
    float amount; // slider, 0.0, 2.0, 0.4, Amount
    float blend; // slider, 0.0, 1.0, 0.0, Blend
} PostUniforms;

fragment half4 postFragment(VertexData in [[stage_in]],
                            constant PostUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
                            texture2d<half, access::sample> sourceTex [[texture(FragmentTextureCustom0)]],
                            texture2d<half, access::sample> halationTex [[texture(FragmentTextureCustom1)]])
{
    half4 source = SAMPLER_FNC(sourceTex, in.texcoord);
    half4 halation = SAMPLER_FNC(halationTex, in.texcoord);
    
    half3 bias = half3(uniforms.tint.rgb * uniforms.tint.a * uniforms.amount);
    
    half3 resultA = source.rgb + halation.rgb * bias;
    half3 resultS = blendScreen(source.rgb , halation.rgb * bias);
    half3 result = mix(resultS, resultA, uniforms.blend);
    result = max(result, half3(0.0));

    return half4( result , source.a);
}
