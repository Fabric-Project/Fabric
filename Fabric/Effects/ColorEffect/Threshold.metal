//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"
#include "../../lygia/math/adaptiveThreshold.msl"
#include "../../lygia/color/luminance.msl"

typedef struct {
    float threshold; // slider, 0.0, 1.0, 0.5, Threshold
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{
    half4 color = SAMPLER_FNC( renderTex, in.texcoord );
    half luma = luminance(color);
    half thresh = luma < uniforms.threshold ? 0.0 : 1.0;
    
    return half4( half3(thresh), color.a);
}
