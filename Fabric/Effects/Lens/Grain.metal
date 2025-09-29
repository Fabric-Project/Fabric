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
    float amount; // slider, 0.0, 100.0, 0.0, Amount
    float resolution; // slider, 0.01, 1.0, 0.1, Resolution
    float time; // slider, 0.0, 1.0, 0.1, Time
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{
    constexpr sampler s = sampler( min_filter::linear, mag_filter::linear );

    half4 color = renderTex.sample( s, in.texcoord );

    uint width = renderTex.get_width();
    uint height = renderTex.get_height();

    half3 g = grain(renderTex, in.texcoord, float2(width, height) * uniforms.resolution , uniforms.time, uniforms.amount);

    color.rgb = g;

    return color;
}
