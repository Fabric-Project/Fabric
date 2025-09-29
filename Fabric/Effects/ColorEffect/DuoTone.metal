//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"

typedef struct {
    float3 low; // color, 0.0, 1.0, 1.0, Dark Color
    float3 high; // color, 0.0, 1.0, 1.0, Light Color
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{
    half4 color = SAMPLER_FNC( renderTex, in.texcoord );
    half3 rgb = mix( half3(uniforms.low),
                     half3(uniforms.high),
                    color.rgb);
    
    return half4( rgb, color.a);
}
