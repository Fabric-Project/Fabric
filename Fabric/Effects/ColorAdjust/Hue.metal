//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>
#define HUESHIFT_AMOUNT

#include "../../lygia/sampler.msl"
#include "../../lygia/color/hueShift.msl"

typedef struct {
    float hue; // slider, 0.0, 1.0, 0.0, Hue
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{
    half4 color = SAMPLER_FNC( renderTex, in.texcoord );

    return half4( hueShift( float4(color), uniforms.hue) );
}
