#include <metal_stdlib>
using namespace metal;

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"

static inline float luma(float3 rgb) {
    return dot(rgb, float3(0.299f, 0.587f, 0.114f));
}

fragment half4 postFragment(
    VertexData in [[stage_in]],
    texture2d<half, access::sample> tex [[texture(FragmentTextureCustom0)]]
) {
    float2 uv = in.texcoord;

    float2 texSize = float2(tex.get_width(), tex.get_height());
    float2 rcpFrame = 1.0f / texSize;

    // Rebuild pixel-space position
    float2 pos = uv * texSize;

    // FXAA sub-pixel offset (matches original shader)
    const float FXAA_SUBPIX_SHIFT = 0.25f;
    float2 posM = pos - (0.5f + FXAA_SUBPIX_SHIFT);

    // Sample positions (pixel space → UV at sample time)
    float2 uvM  = pos * rcpFrame;
    float2 uvNW = (posM + float2(0.0f, 0.0f)) * rcpFrame;
    float2 uvNE = (posM + float2(1.0f, 0.0f)) * rcpFrame;
    float2 uvSW = (posM + float2(0.0f, 1.0f)) * rcpFrame;
    float2 uvSE = (posM + float2(1.0f, 1.0f)) * rcpFrame;

    float3 rgbNW = float3(SAMPLER_FNC(tex, uvNW).rgb);
    float3 rgbNE = float3(SAMPLER_FNC(tex, uvNE).rgb);
    float3 rgbSW = float3(SAMPLER_FNC(tex, uvSW).rgb);
    float3 rgbSE = float3(SAMPLER_FNC(tex, uvSE).rgb);
    float3 rgbM  = float3(SAMPLER_FNC(tex, uvM ).rgb);

    float lumaNW = luma(rgbNW);
    float lumaNE = luma(rgbNE);
    float lumaSW = luma(rgbSW);
    float lumaSE = luma(rgbSE);
    float lumaM  = luma(rgbM);

    float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
    float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));

    // Edge direction (pixel space)
    float2 dir;
    dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
    dir.y =  ((lumaNW + lumaSW) - (lumaNE + lumaSE));

    const float FXAA_REDUCE_MIN = 1.0f / 128.0f;
    const float FXAA_REDUCE_MUL = 1.0f / 8.0f;
    const float FXAA_SPAN_MAX   = 8.0f;

    float dirReduce = max(
        (lumaNW + lumaNE + lumaSW + lumaSE) * (0.25f * FXAA_REDUCE_MUL),
        FXAA_REDUCE_MIN
    );

    float rcpDirMin = 1.0f / (min(abs(dir.x), abs(dir.y)) + dirReduce);
    dir = clamp(dir * rcpDirMin,
                float2(-FXAA_SPAN_MAX),
                float2( FXAA_SPAN_MAX));

    // Convert direction to UV space only here
    float2 dirUV = dir * rcpFrame;

    half4 rgbA = 0.5h * (
        SAMPLER_FNC(tex, uvM + dirUV * (1.0f/3.0f - 0.5f)) +
        SAMPLER_FNC(tex, uvM + dirUV * (2.0f/3.0f - 0.5f))
    );

    half4 rgbB = rgbA * 0.5h + 0.25h * (
        SAMPLER_FNC(tex, uvM + dirUV * (0.0f/3.0f - 0.5f)) +
        SAMPLER_FNC(tex, uvM + dirUV * (3.0f/3.0f - 0.5f))
    );

    float lumaB = luma(float3(rgbB.rgb));

    return ((lumaB < lumaMin) || (lumaB > lumaMax)) ? rgbA : rgbB;
}
