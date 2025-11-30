//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
#include <metal_stdlib>
using namespace metal;

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"

// Uniforms → Fabric UI slider
typedef struct {
    float amount;   // slider, 0.0, 2.0, 0.0, Amount
} PostUniforms;

fragment half4 postFragment( VertexData                        in        [[stage_in]],
                             constant PostUniforms            &uniforms  [[buffer( FragmentBufferMaterialUniforms )]],
                             texture2d<half, access::sample>   tex        [[texture( FragmentTextureCustom0 )]] )
{
    float2 uv = in.texcoord;

    half4 input0 = SAMPLER_FNC(tex, uv);
    half3 rgb = input0.rgb;

    // Primary mattes
    half3 redmatte   = half3(rgb.r - (rgb.g + rgb.b) * 0.5h);
    half3 greenmatte = half3(rgb.g - (rgb.r + rgb.b) * 0.5h);
    half3 bluematte  = half3(rgb.b - (rgb.r + rgb.g) * 0.5h);

    // Invert mattes
    redmatte   = 1.0h - redmatte;
    greenmatte = 1.0h - greenmatte;
    bluematte  = 1.0h - bluematte;

    // Apply matte combinations to channels
    half3 red   =  greenmatte * bluematte * rgb.r;
    half3 green =  redmatte   * bluematte * rgb.g;
    half3 blue  =  redmatte   * greenmatte * rgb.b;

    // Recombine: use per-channel from the corresponding vector
    half4 result = half4(red.r, green.g, blue.b, input0.a);

    return mix(input0, result, half(uniforms.amount));
}
