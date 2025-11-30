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
    float amount;    // slider, 0.0, 1.0, 0.5, Amount
    float exposure;  // slider, 0.0, 4.0, 1.0, Exposure
    float diffusion; // slider, 0.0, 1.0, 0.5, Diffusion
    float blur;      // slider, 0.0, 0.02, 0.005, BlurRadius
} PostUniforms;

// Luma coefficients (Rec. 601-ish)
constant half4 kLumCoeff = half4(0.299h, 0.587h, 0.114h, 0.0h);

// sqrt(2) from Metal's constants
constant float kSqrt2 = M_SQRT2_F;

fragment half4 postFragment( VertexData                        in        [[stage_in]],
                             constant PostUniforms            &uniforms  [[buffer( FragmentBufferMaterialUniforms )]],
                             texture2d<half, access::sample>   renderTex [[texture( FragmentTextureCustom0 )]] )
{
    float2 uv = in.texcoord;
    float  b  = uniforms.blur;

    // 3x3 neighborhood UVs
    float2 uv0 = uv;
    float2 uv1 = uv + float2(-b, -b);
    float2 uv2 = uv + float2( b, -b);
    float2 uv3 = uv + float2( b,  b);
    float2 uv4 = uv + float2(-b,  b);
    float2 uv5 = uv + float2( 0.0f, -b);
    float2 uv6 = uv + float2( 0.0f,  b);
    float2 uv7 = uv + float2( b,  0.0f);
    float2 uv8 = uv + float2(-b,  0.0f);

    // Clamp UVs to [0,1] to avoid sampling outside
    uv1 = clamp(uv1, 0.0f, 1.0f);
    uv2 = clamp(uv2, 0.0f, 1.0f);
    uv3 = clamp(uv3, 0.0f, 1.0f);
    uv4 = clamp(uv4, 0.0f, 1.0f);
    uv5 = clamp(uv5, 0.0f, 1.0f);
    uv6 = clamp(uv6, 0.0f, 1.0f);
    uv7 = clamp(uv7, 0.0f, 1.0f);
    uv8 = clamp(uv8, 0.0f, 1.0f);

    // Samples
    half4 input0 = SAMPLER_FNC(renderTex, uv0);
    half4 input1 = SAMPLER_FNC(renderTex, uv1);
    half4 input2 = SAMPLER_FNC(renderTex, uv2);
    half4 input3 = SAMPLER_FNC(renderTex, uv3);
    half4 input4 = SAMPLER_FNC(renderTex, uv4);
    half4 input5 = SAMPLER_FNC(renderTex, uv5);
    half4 input6 = SAMPLER_FNC(renderTex, uv6);
    half4 input7 = SAMPLER_FNC(renderTex, uv7);
    half4 input8 = SAMPLER_FNC(renderTex, uv8);

    // Blur (note original used *0.125 with 9 taps)
    half4 blurresult = (input0 + input1 + input2 + input3 +
                        input4 + input5 + input6 + input7 + input8) * 0.125h;

    // Luma of original and blurred
    half4 origLuma = half4(dot(input0, kLumCoeff));
    half4 luma     = half4(dot(blurresult, kLumCoeff));

    // Diffusion-driven contrast (orig vs blurred luma)
    half4 contrast = mix(origLuma, luma, half(uniforms.diffusion));

    // Exposure shaping (same as GLSL: log2(pow(exposure + sqrt(2), 2.0)) * luma)
    float expoBase  = uniforms.exposure + kSqrt2;
    float expoScale = log2(expoBase * expoBase);
    half4 exposureResult = half4(expoScale) * luma;

    // Blend between original luma and exposure-adjusted result, weighted by luma * contrast
    half4 result = mix(origLuma, exposureResult, luma * contrast);

    // Mix back with original RGB, keep original alpha
    result = mix(input0, result, half(uniforms.amount));
    result.a = input0.a;

    return result;
}
