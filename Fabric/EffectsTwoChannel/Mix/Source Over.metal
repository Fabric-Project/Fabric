//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Source Over blend mode

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"
#include "../../lygia/color/layer.msl"
#include "../../lygia/color/composite/sourceOver.msl"
#include "../../lygia/color/space/gamma2linear.msl"
#include "../../lygia/color/space/linear2gamma.msl"
#include "../../Shaders/FabricImageTextureTransform.metal"

typedef struct {
    float amount; // slider, 0.0, 1.0, 0.0, Amount
} PostUniforms;


fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    constant float4x4 *imageTransforms [[buffer(FragmentBufferCustom10)]],
    texture2d<half, access::sample> tex0 [[texture( FragmentTextureCustom0 )]],
    texture2d<half, access::sample> tex1 [[texture( FragmentTextureCustom1 )]] )
{
    half4 amount = half4(uniforms.amount);
    half4 srcColor = gamma2linear(SAMPLER_FNC(tex0, fabricTextureCoordinate(imageTransforms[0], in.texcoord)));
    half4 dstColor = gamma2linear(SAMPLER_FNC(tex1, fabricTextureCoordinate(imageTransforms[1], in.texcoord)));

    half4 blend = compositeSourceOver(srcColor, dstColor);

//    float4 mix1 = mix(srcColor, blend, clamp( mix(0.0, 2.0, amount), 0.0, 1.0 ) );
//    float4 mix2 = mix(dstColor, blend, clamp( mix(2.0, 0.0, amount), 0.0, 1.0 ) );

    return  linear2gamma(blend);
}
