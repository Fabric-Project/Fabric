//
//  FadeCurve.metal
//  
//
//  Created by Toby Harris on 07/10/2025.
//

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"

typedef struct {
    float amount; // slider, 0.0, 1.0, 0.0, Amount
    float additiveAmount; // slider, 0.0, 1.0, 0.0, Curve
} PostUniforms;


fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<half, access::sample> tex0 [[texture( FragmentTextureCustom0 )]],
    texture2d<half, access::sample> tex1 [[texture( FragmentTextureCustom1 )]] )
{
    half amount = half(uniforms.amount);
    half additiveAmount = 1.0h + half(uniforms.additiveAmount);
    half4 srcColor = SAMPLER_FNC( tex0, in.texcoord );
    half4 dstColor = SAMPLER_FNC( tex1, in.texcoord );
    
    half4 result;
    result.rgb = mix(0.0h, srcColor.rgb, min((1.0h - amount) * additiveAmount, 1.0h)) +
                 mix(0.0h, dstColor.rgb, min(amount * additiveAmount, 1.0h));
    result.a = 1.0h;
    
    return result;
}
