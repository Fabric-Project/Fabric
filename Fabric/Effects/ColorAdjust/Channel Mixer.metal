#include <metal_stdlib>
using namespace metal;

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"


// Uniforms → Fabric UI controls
typedef struct {
    float3 red;    // slider3, 0.0, 2.0, 1,0, Red
    float3 green;  // slider3, 0.0, 2.0, 1,0, Green
    float3 blue;   // slider3, 0.0, 2.0, 1,0, Blue
    float  amount; // slider, 0.0, 1.0, 0.0, Amount
} PostUniforms;

fragment half4 postFragment( VertexData                        in        [[stage_in]],
                             constant PostUniforms            &uniforms  [[buffer( FragmentBufferMaterialUniforms )]],
                             texture2d<half, access::sample>   tex        [[texture( FragmentTextureCustom0 )]] )
{
    float2 uv = in.texcoord;

    half4 input0 = SAMPLER_FNC(tex, uv);
    half3 rgb = input0.rgb;

    // Channel mixing
    half3 redChannel   = half3(rgb.r) * half3(uniforms.red);
    half3 greenChannel = half3(rgb.g) * half3(uniforms.green);
    half3 blueChannel  = half3(rgb.b) * half3(uniforms.blue);

    half3 resultRGB = redChannel + greenChannel + blueChannel;

    half4 result = half4(resultRGB, input0.a);

    return mix(input0, result, half(uniforms.amount));
}
