//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"
#include "../../lygia/color/levels.msl"


typedef struct {
    float3 iMin; // input, 0.0, Input Min
    float3 iMax; // input, 1.0, Input Max
    float3 oMin; // input, 0.0, Output Min
    float3 oMax; // input, 1.0, Output Max
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{
    half4 color = SAMPLER_FNC( renderTex, in.texcoord );

    return half4( levelsOutputRange(  levelsInputRange(float4(color), uniforms.iMin, uniforms.iMax), uniforms.oMin, uniforms.oMax) );
}
