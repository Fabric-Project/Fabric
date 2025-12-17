#include <metal_stdlib>
using namespace metal;

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"
#include "../../lygia/math/mod.msl"


typedef struct {
    float amount;       // slider, 0.0, 1.0, 1.0, Amount (overall)

    float bgAmount;     // slider, 0.0, 1.0, 1.0, Background Amount
    float fgAmount;     // slider, 0.0, 1.0, 1.0, Foreground Amount

    float density;      // slider, 1.0, 100.0, 9.0, Line Density
    float width;        // slider, 0.1, 50.0, 5.0, Line Width
    float angle;        // slider, -3.14159, 3.14159, 0.0, Angle

    float hatch1;       // slider, 0.0, 1.0, 0.8, Hatch1 Threshold
    float hatch2;       // slider, 0.0, 1.0, 0.6, Hatch2 Threshold
    float hatch3;       // slider, 0.0, 1.0, 0.3, Hatch3 Threshold
    float hatch4;       // slider, 0.0, 1.0, 0.15, Hatch4 Threshold

    float h1Bright;     // slider, 0.0, 1.0, 0.8, Hatch1 Brightness
    float h2Bright;     // slider, 0.0, 1.0, 0.6, Hatch2 Brightness
    float h3Bright;     // slider, 0.0, 1.0, 0.3, Hatch3 Brightness
    float h4Bright;     // slider, 0.0, 1.0, 0.0, Hatch4 Brightness

    float edgeStrength; // slider, 0.0, 10.0, 1.0, Edge Strength
    float edgeMix;      // slider, 0.0, 1.0, 1.0, Edge Mix

    float4 fgColor;     // color, Foreground Color
    float4 bgColor;     // color, Background Color
} PostUniforms;

static inline float luma(float3 c) {
    return dot(c, float3(0.2126f, 0.7152f, 0.0722f));
}

static inline float2 rotate2D(float2 p, float a) {
    float s = sin(a);
    float c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

static inline float lumaSample(texture2d<half, access::sample> tex, float2 uv) {
    half4 c = SAMPLER_FNC(tex, clamp(uv, 0.0f, 1.0f));
    return luma(float3(c.rgb));
}

fragment half4 postFragment( VertexData                       in   [[stage_in]],
                             constant PostUniforms           &u    [[buffer( FragmentBufferMaterialUniforms )]],
                             texture2d<half, access::sample>  tex0 [[texture( FragmentTextureCustom0 )]] )
{
    float2 uv = in.texcoord;

    half4 src = SAMPLER_FNC(tex0, uv);
    float lum = luma(float3(src.rgb));

    // Duotone ramp based on luma:
    // lum=0 (dark) -> fgColor, lum=1 (light) -> bgColor
    half3 fgC = half3(u.fgColor.rgb);
    half3 bgC = half3(u.bgColor.rgb);
    half3 duo = mix(fgC, bgC, half(lum));

    // Build background and foreground layers with independent mixing vs original image
    // bgLayer: 0 => original image, 1 => bgColor (but we apply "light side" of duo via bgColor dominance)
    // fgLayer: 0 => original image, 1 => fgColor (dark side)
    half3 bgLayer = mix(src.rgb, bgC, half(u.bgAmount));
    half3 fgLayer = mix(src.rgb, fgC, half(u.fgAmount));

    // Also keep the duotone ramp available as the "paper-to-ink" mapping
    // We'll use it to shade the hatch brightness (so color always comes from fg/bg concept).
    // Base "paper" is background layer; "ink" is foreground layer.
    half3 paper = bgLayer;
    half3 ink   = fgLayer;

    // Pixel-space coords for hatch pattern
    float2 texSize = float2(tex0.get_width(), tex0.get_height());
    float2 coord   = uv * texSize;

    // Rotate hatch space around center
    float2 centered = coord - 0.5f * texSize;
    float2 rc = rotate2D(centered, u.angle) + 0.5f * texSize;

    float d = max(u.density, 0.0001f);
    float w = max(u.width,   0.0f);

    // Hatch brightness mask (1 = no ink, 0 = solid ink), like original logic
    // We’ll store it as "hatchValue" where lower => darker/inkier.
    float hatchValue = 1.0f;

    if (lum < u.hatch1) {
        if (mod(rc.x + rc.y, d) <= w) hatchValue = min(hatchValue, u.h1Bright);
    }
    if (lum < u.hatch2) {
        if (mod(rc.x - rc.y, d) <= w) hatchValue = min(hatchValue, u.h2Bright);
    }
    if (lum < u.hatch3) {
        if (mod(rc.x + rc.y, d) <= w) hatchValue = min(hatchValue, u.h3Bright);
    }
    if (lum < u.hatch4) {
        if (mod(rc.x - rc.y, d) <= w) hatchValue = min(hatchValue, u.h4Bright);
    }

    // Convert hatchValue into an "ink mask":
    // hatchValue close to 0 => more ink, close to 1 => less ink.
    float inkMask = clamp(1.0f - hatchValue, 0.0f, 1.0f);

    // Sobel-ish edge detection (same as prior)
    float2 texel = 1.0f / max(texSize, float2(1.0f));
    float gx = 0.0f;
    gx += -1.0f * lumaSample(tex0, uv + texel * float2(-1.0f, -1.0f));
    gx += -2.0f * lumaSample(tex0, uv + texel * float2(-1.0f,  0.0f));
    gx += -1.0f * lumaSample(tex0, uv + texel * float2(-1.0f,  1.0f));
    gx +=  1.0f * lumaSample(tex0, uv + texel * float2( 1.0f, -1.0f));
    gx +=  2.0f * lumaSample(tex0, uv + texel * float2( 1.0f,  0.0f));
    gx +=  1.0f * lumaSample(tex0, uv + texel * float2( 1.0f,  1.0f));

    float gy = 0.0f;
    gy += -1.0f * lumaSample(tex0, uv + texel * float2(-1.0f, -1.0f));
    gy += -2.0f * lumaSample(tex0, uv + texel * float2( 0.0f, -1.0f));
    gy += -1.0f * lumaSample(tex0, uv + texel * float2( 1.0f, -1.0f));
    gy +=  1.0f * lumaSample(tex0, uv + texel * float2(-1.0f,  1.0f));
    gy +=  2.0f * lumaSample(tex0, uv + texel * float2( 0.0f,  1.0f));
    gy +=  1.0f * lumaSample(tex0, uv + texel * float2( 1.0f,  1.0f));

    float g = (gx * gx + gy * gy) * u.edgeStrength;
    float edgeInk = clamp(g, 0.0f, 1.0f);
    edgeInk = mix(0.0f, edgeInk, u.edgeMix);

    // Combine hatch ink + edge ink (union)
    float combinedInk = clamp(max(inkMask, edgeInk), 0.0f, 1.0f);

    // Final duotone application:
    // - Paper is background layer
    // - Ink is foreground layer
    // combinedInk decides where ink replaces paper
    half3 duoOut = mix(paper, ink, half(combinedInk));

    // (Optional) If you want the duotone ramp to influence paper/ink further, you can multiply:
    // duoOut *= duo;
    // Leaving it off keeps "paper" and "ink" clean and controllable via bg/fg amounts + colors.

    half4 outColor = half4(duoOut, src.a);

    return mix(src, outColor, half(u.amount));
}
