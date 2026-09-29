//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Maps luminance to a two-colour gradient

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"
#include "../../Shaders/FabricImageTextureTransform.metal"

typedef struct {
    float4 low; // color, 0.0, 0.0, 0.0, 1.0, Dark Color
    float4 high; // color, 1.0, 1.0, 1.0, 1.0, Light Color
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    constant float4x4 *imageTransforms [[buffer(FragmentBufferCustom10)]],
    texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{
    half4 color = SAMPLER_FNC( renderTex, fabricTextureCoordinate(imageTransforms[0], in.texcoord));
    half3 rgb = mix( half3(uniforms.low.rgb),
                     half3(uniforms.high.rgb),
                    color.rgb);
    
    return half4( rgb, color.a);
}
