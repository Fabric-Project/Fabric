//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//

#include "../../lygia/sampler.msl"
#include "../../lygia/sdf/opUnion.msl"


typedef struct {
    float amount; // slider, 0.0, 1.0, 0.0, Softness

} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<float, access::sample> sdfa [[texture( FragmentTextureCustom0 )]],
    texture2d<float, access::sample> sdfb [[texture( FragmentTextureCustom1 )]] )
{    
    float2 coords = in.texcoord;

    float sdf1 = SAMPLER_FNC(sdfa, coords).r;
    float sdf2 = SAMPLER_FNC(sdfb, coords).r;

    // Read pixel intensities from the current and reference frames
    return half4(opUnion(sdf1, sdf2, uniforms.amount));
}
