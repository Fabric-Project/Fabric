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
#define SAMPLER sampler( min_filter::linear, mag_filter::linear, address::mirrored_repeat )

#include "../../lygia/sampler.msl"
#include "../../lygia/math/radians.msl"
#include "../../lygia/math/rotate2d.msl"

// Uniforms → Fabric UI sliders
typedef struct {
    float    amount;   // slider, 0.01, 1.0, 0.5, Amount
    float    length;   // slider, 0.0, 1.0, 0.5, Length
    float    angle;   // slider, -180.0, 180.0, 0.0, Angle
} PostUniforms;

fragment half4 postFragment( VertexData                        in        [[stage_in]],
                             constant PostUniforms            &uniforms  [[buffer( FragmentBufferMaterialUniforms )]],
                             texture2d<half, access::sample>   imageTex  [[texture( FragmentTextureCustom0 )]],
                             texture2d<half, access::sample>   lutTex    [[texture( FragmentTextureCustom1 )]] )
{
    float2 uv = in.texcoord; // normalized [0, 1]

    // Base image sample
    half4 input0 = SAMPLER_FNC(imageTex, uv);

    // Rotate sampling point around center (0.5, 0.5)
    float2 point = uv;
    float2 centered = point - 0.5f;
    centered = rotate2d( radians(uniforms.angle) ) * centered; // rotated in [-0.5, 0.5]
    point = centered + 0.5f;

    // Leak length shaping
    // leakIntensity = pow(point.y, 1.0 + ((1.0 - length) * 19.0));
    float leakExponent = 1.0f + ((1.0f - uniforms.length) * 19.0f);
    float leakIntensity = clamp( pow(point.y, leakExponent), 0.0, 1.0) ;

    // Adjust gamma/brightness by amount
    float safeAmount = max(uniforms.amount, 0.0001f);
    leakIntensity = pow(leakIntensity, 1.0f / safeAmount);

    // Sample LUT (1D across X, y=0), wrapping X
    float2 lutUV = point;// float2(fract(point.x), uv.y);
    half4 leak = SAMPLER_FNC(lutTex, lutUV);

    leak *= leakIntensity; //pow(leak * leakIntensity, vec4(1.0/(leakIntensity)));
//    float safeLeakI = max(leakIntensity, 0.0001f);
//    half  hLeakI    = half(leakIntensity);
//    half4 hInvLeakI = half4(half(1.0f / safeLeakI));

//    leak = pow(leak * hLeakI, hInvLeakI);

    // Add to base image
    leak += input0;

    // Blend with original
    return mix(input0, leak, half(uniforms.amount));
}
