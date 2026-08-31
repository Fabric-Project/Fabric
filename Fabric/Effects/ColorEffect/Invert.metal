//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Inverts image colours

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"
#include "../../Shaders/FabricImageTextureTransform.metal"

typedef struct {
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    constant float4x4 *imageTransforms [[buffer(FragmentBufferCustom10)]],
    texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{
    const float2 imageUV = fabricTextureCoordinate(imageTransforms[0], in.texcoord);
    half4 color = SAMPLER_FNC(renderTex, imageUV);

    return half4(1.0 - color.rgb, color.a);
}
