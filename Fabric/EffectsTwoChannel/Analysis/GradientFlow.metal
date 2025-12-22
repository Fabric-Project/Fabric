//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//

#include <metal_stdlib>
using namespace metal;

// #define SAMPLEDOF_DEBUG
#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>
#include "../../lygia/sampler.msl"
#include "../../lygia/color/luminance.msl"

struct PostUniforms {
    float2 scale; // slider, 0.0, 10.0, 0.0, Scale
    float2 offset; // slider, 0.0, 10.0, 0.0, Offset
    float  lambda; // slider, 0.0, 1.0, 0.0, Lambda
};

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &u [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<half, access::sample> tex0 [[texture( FragmentTextureCustom0 )]],
    texture2d<half, access::sample> tex1 [[texture( FragmentTextureCustom1 )]])
{
    
    float2 texSize0 = float2(tex0.get_width(), tex0.get_height());
    float2 texSize1 = float2(tex1.get_width(), tex1.get_height());

    // If tex0/tex1 differ in size, this preserves the slightly-odd behavior
    // of applying offsets in each texture's own pixel space.
    float2 x0 = float2(u.offset.x, 0.0) / texSize0;
    float2 y0 = float2(0.0, u.offset.y) / texSize0;
    float2 x1 = float2(u.offset.x, 0.0) / texSize1;
    float2 y1 = float2(0.0, u.offset.y) / texSize1;

    // Original had texcoord0 and texcoord1; in post we usually have one uv.
    // Keep the “two coord sets” concept by treating both as the same uv.
    float2 tc0 = in.texcoord;
    float2 tc1 = in.texcoord;

    half4 a = SAMPLER_FNC(tex0, tc0);
    half4 b = SAMPLER_FNC(tex1, tc1);

    // get the difference
    half4 curdif = b - a;

    // calculate the gradient (per-channel), summing gradients from both frames
    half4 gradx = SAMPLER_FNC(tex1, tc1 + x1) - SAMPLER_FNC(tex1, tc1 - x1);
    gradx +=       SAMPLER_FNC(tex0, tc0 + x0) - SAMPLER_FNC(tex0, tc0 - x0);

    half4 grady = SAMPLER_FNC(tex1, tc1 + y1) - SAMPLER_FNC(tex1, tc1 - y1);
    grady +=       SAMPLER_FNC(tex0, tc0 + y0) - SAMPLER_FNC(tex0, tc0 - y0);

    half4 gradmag = sqrt((gradx * gradx) + (grady * grady) + half4(u.lambda));

    half4 vx = curdif * (gradx / gradmag) * half(u.scale.x);
//    half vxd = length_squared(vx);// .r; // assumes greyscale (preserved)
//
//    // format output for flowrepos, out(-x,+x,-y,+y)
//    half2 xout = half2(max(vxd, 0.0h), fabs(min(vxd, 0.0h))) * half(u.scale.x);

    half4 vy = curdif * (grady / gradmag) * half(u.scale.y);
//    half vyd = length_squared(vy);//.r; // assumes greyscale (preserved)
//
//    half2 yout = half2(max(vyd, 0.0h), fabs(min(vyd, 0.0h))) * half(u.scale.y);

//    return half4(xout.x, xout.y, yout.x, yout.y);
    return half4(vx.x, vx.y, vy.x, vy.y);

//    return clamp(half4(xout.x, xout.y, yout.x, yout.y), 0.0f, 1.0f);
}
