//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"
#include "../../lygia/color/whiteBalance.msl"


typedef struct {
    float temp; // slider, -1.0, 1.0, 0.0, Tempurature
    float tint; // slider, -1.0, 1.0, 0.0, Tint
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{
    half4 color = SAMPLER_FNC( renderTex, in.texcoord );

    return half4( whiteBalance( float4(color), uniforms.temp, uniforms.tint) );
}
