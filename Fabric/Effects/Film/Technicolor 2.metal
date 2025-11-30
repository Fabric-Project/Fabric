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

// Uniforms → Fabric UI sliders
typedef struct {
    float amount;   // slider, 0.0, 2.0, 0.0, Amount
} PostUniforms;

fragment half4 postFragment( VertexData                        in        [[stage_in]],
                             constant PostUniforms            &uniforms  [[buffer( FragmentBufferMaterialUniforms )]],
                             texture2d<half, access::sample>   tex        [[texture( FragmentTextureCustom0 )]] )
{
    float2 uv = in.texcoord;

    half4 input0 = SAMPLER_FNC(tex, uv);

    // Filters (Metal half4 constants)
    const half4 redfilter        = half4(1.0h, 0.0h, 0.0h, 1.0h);
    const half4 bluegreenfilter  = half4(0.0h, 1.0h, 1.0h, 1.0h);

    const half4 cyanfilter       = half4(0.0h, 1.0h, 0.5h, 1.0h);
    const half4 magentafilter    = half4(1.0h, 0.0h, 0.25h, 1.0h);

    // Channel masking
    half4 redrecord       = input0 * redfilter;
    half4 bluegreenrecord = input0 * bluegreenfilter;

    // “Negatives”
    half4 rednegative       = half4(redrecord.r);
    half4 bluegreennegative = half4((bluegreenrecord.g + bluegreenrecord.b) * 0.5h);

    // Add filters back
    half4 redoutput       = rednegative       + cyanfilter;
    half4 bluegreenoutput = bluegreennegative + magentafilter;

    // Multiply channels
    half4 result = redoutput * bluegreenoutput;

    // Mix with original
    return mix(input0, result, half(uniforms.amount));
}
