//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//


#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"
#include "../../lygia/color/blend.msl"
#include "../../lygia/color/composite/sourceOver.msl"

typedef struct {
    float amount; // slider, -1.0, 2.0, 0.0, Amount
} PostUniforms;


fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<half, access::sample> tex0 [[texture( FragmentTextureCustom0 )]],
    texture2d<half, access::sample> tex1 [[texture( FragmentTextureCustom1 )]] )
{
    half amount = half(uniforms.amount);
    half4 srcColor = SAMPLER_FNC( tex0, in.texcoord );
    half4 dstColor = SAMPLER_FNC( tex1, in.texcoord );
    
    half4 result;
    
    result = mix(srcColor, dstColor, amount);
    
    return result;
}
