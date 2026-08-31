//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Blends two signed distance fields

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"
#include "../../lygia/color/space/gamma2linear.msl"
#include "../../lygia/color/space/linear2gamma.msl"
#include "../../Shaders/FabricImageTextureTransform.metal"

typedef struct {
    float amount; // slider, 0.0, 1.0, 0.0, Amount

} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    constant float4x4 *imageTransforms [[buffer(FragmentBufferCustom10)]],
    texture2d<half, access::sample> sdfa [[texture( FragmentTextureCustom0 )]],
    texture2d<half, access::sample> sdfb [[texture( FragmentTextureCustom1 )]] )
{    
    float2 coords = in.texcoord;

    float sdf1 = SAMPLER_FNC(sdfa, fabricTextureCoordinate(imageTransforms[0], coords)).r;
  //  sdf1 = gamma2linear(sdf1);

    float sdf2 = SAMPLER_FNC(sdfb, fabricTextureCoordinate(imageTransforms[1], coords)).r;
//    sdf2 = gamma2linear(sdf2);

    // Read pixel intensities from the current and reference frames
    return half4( mix(sdf1, sdf2, uniforms.amount) );
}
