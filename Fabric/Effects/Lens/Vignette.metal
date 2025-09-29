//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>
#define GRAIN_TYPE half3

#include "../../lygia/sampler.msl"
#include "../../lygia/distort/grain.msl"

typedef struct {
    float radius; // slider, 0.0, 1.0, 0.5, Radius
    float smoothness; // slider, 0.01, 1.0, 0.1, Smoothness
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{
    constexpr sampler s = sampler( min_filter::linear, mag_filter::linear );

    float v = uniforms.radius - distance(in.texcoord, float2(0.5));
    v = smoothstep(-uniforms.smoothness, uniforms.smoothness, v);
    
    half4 color = renderTex.sample( s, in.texcoord );

    return color * v;
}
