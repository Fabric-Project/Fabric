//
//  Halation Extract.metal
//  Fabric
//
// description: Extracts soft color highlights for halation blur

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"
#include "../../Shaders/FabricImageTextureTransform.metal"

typedef struct {
    float threshold; // slider, 0.0, 2.0, 0.75, Threshold
    float softness; // slider, 0.0, 1.0, 0.15, Softness
    float gain; // slider, 0.0, 4.0, 1.0, Gain
} PostUniforms;

fragment half4 postFragment(VertexData in [[stage_in]],
                            constant PostUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
                            constant float4x4 *imageTransforms [[buffer(FragmentBufferCustom10)]],
                            texture2d<half, access::sample> renderTex [[texture(FragmentTextureCustom0)]])
{
    half4 color = SAMPLER_FNC(renderTex, fabricTextureCoordinate(imageTransforms[0], in.texcoord));
    float3 sourceColor = float3(color.rgb);
    float luma = dot(sourceColor, float3(0.2126f, 0.7152f, 0.0722f));
    float softness = max(uniforms.softness, 0.0001f);
    float mask = smoothstep(uniforms.threshold - softness,
                            uniforms.threshold + softness,
                            luma);
    float3 highlights = sourceColor * (mask * uniforms.gain);

    return half4(half3(highlights), half(mask));
}
