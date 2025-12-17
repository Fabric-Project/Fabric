#include <metal_stdlib>
using namespace metal;

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"
#include "../../lygia/color/space/cmyk2rgb.msl"
#include "../../lygia/color/space/rgb2cmyk.msl"
#include "../../lygia/math/radians.msl"

// Uniforms -> Fabric UI
typedef struct {
    float  amount;      // slider, 0.0, 1.0, 1.0, Amount

    float4 dotSize;     // slider, 1.0, 200.0, 60.0, Dot Size
    float4 angles;      // slider, 0.0, 180.0, 15.0, Angles
    float  sharpness;   // slider, 0.0001, 0.2, 0.02, Sharpness
    float  rgbContribution; // slider, 0.0, 1.0, 0.5, RGB Contribution
    float4 paper;       // color, Paper
    float4 cColor;      // color, Cyan
    float4 mColor;      // color, Magenta
    float4 yColor;      // color, Yellow
    float4 kColor;      // color, Black
} PostUniforms;


static inline float2 rotate2D(float2 p, float aRad) {
    float s = sin(aRad);
    float c = cos(aRad);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Returns (dist, dotMask) where dotMask is 0..1 (like original smoothstep)
static inline float2 amHalftone(float channel, float angleDeg, float scale, float sharpness, float2 uv) {
    // In the GLSL: sttemp = scale * (texcoord0 / imageSize)
    // Here: texcoord is already normalized, so uv is equivalent.
    float2 st = (scale) * uv;

    float a = radians(angleDeg);
    float2 rot = rotate2D(st, a);

    // GLSL mod(rotVec, 1.0) -> make it positive-wrap like GLSL mod
    float2 cell = rot - floor(rot); // == fract(rot)

    float2 d = cell - 0.5f;
    float dist = length(d);

    float blackness = 1.0f - clamp(channel, 0.0f, 1.0f);
    float radius = 0.5f * sqrt(blackness);

    float s = max(sharpness, 1e-6f);
    float dotMask = smoothstep(radius - s, radius + s, dist);

    return float2(dist, dotMask);
}

fragment half4 postFragment( VertexData                        in        [[stage_in]],
                             constant PostUniforms            &u         [[buffer( FragmentBufferMaterialUniforms )]],
                             texture2d<half, access::sample>   tex0      [[texture( FragmentTextureCustom0 )]] )
{
    float2 uv = in.texcoord;

    half4 src = SAMPLER_FNC(tex0, uv);
    float3 rgb = float3(src.rgb);

    // Convert to CMYK (C,M,Y,K)
    float4 cmyk = rgb2cmyk(rgb);

    // Matches your original "minColor" usage (derived from CMY)
    float minColor = min(cmyk.x, min(cmyk.y, cmyk.z)) * 0.5f;

    // "Clear" / paper contribution (your original did (paper.rgb*paper.a)/4)
    float4 paper = float4(u.paper);
    float4 clear = float4((paper.rgb * paper.a) / 4.0f, paper.a);

    // Halftone dots per channel
    float2 cd = amHalftone(cmyk.x, u.angles.x, u.dotSize.x, u.sharpness, uv);
    float2 md = amHalftone(cmyk.y, u.angles.y, u.dotSize.y, u.sharpness, uv);
    float2 yd = amHalftone(cmyk.z, u.angles.z, u.dotSize.z, u.sharpness, uv);
    float2 kd = amHalftone(minColor, u.angles.w, u.dotSize.w, u.sharpness, uv);

    // In original: mix(clear, inkColor, (1 - dotMask))
    // Cyan/Magenta/Yellow use (1 - ink.rgb) * ink.a; Black uses ink.rgb * ink.a
    float4 cInk = float4((1.0f - u.cColor.rgb) * u.cColor.a, u.cColor.a);
    float4 mInk = float4((1.0f - u.mColor.rgb) * u.mColor.a, u.mColor.a);
    float4 yInk = float4((1.0f - u.yColor.rgb) * u.yColor.a, u.yColor.a);
    float4 kInk = float4((u.kColor.rgb) * u.kColor.a, u.kColor.a);

    float4 c = mix(clear, cInk, (1.0f - cd.y));
    float4 m = mix(clear, mInk, (1.0f - md.y));
    float4 y = mix(clear, yInk, (1.0f - yd.y));
    float4 k = mix(clear, kInk, (1.0f - kd.y));

    // Preserve the original compositing logic
    float4 result = float4(1.0f);
    result -= c;
    result -= m;
    result -= y;
    result -= k;

    result = 1.0f - result;
    result *= mix(float4(1.0), float4(rgb, float(src.a)), u.rgbContribution);

    // Overall mix vs source
    half4 outColor = half4(result);
    return mix(src, outColor, half(u.amount));
}
