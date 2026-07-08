//
//  Halation.metal
//  Fabric
//
// description: Adds tinted blurred highlights back into a clean source image

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"

typedef struct {
    float4 tint; // color, 1.0, 0.35, 0.12, 1.0, Tint
    float amount; // slider, 0.0, 2.0, 0.4, Amount
} PostUniforms;

fragment half4 postFragment(VertexData in [[stage_in]],
                            constant PostUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
                            texture2d<half, access::sample> sourceTex [[texture(FragmentTextureCustom0)]],
                            texture2d<half, access::sample> halationTex [[texture(FragmentTextureCustom1)]])
{
    half4 source = SAMPLER_FNC(sourceTex, in.texcoord);
    half4 halation = SAMPLER_FNC(halationTex, in.texcoord);
    float3 result = float3(source.rgb) + float3(halation.rgb) * uniforms.tint.rgb * uniforms.tint.a * uniforms.amount;

    return half4(half3(max(result, float3(0.0f))), source.a);
}
