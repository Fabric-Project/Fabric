//
//  Grain.metal
//  Fabric
//
// description: Adds luminance-weighted, spatially correlated, multi-scale film grain, ported from CineGrain https://github.com/mr-berndt/cinegrain

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"

typedef struct {
    float intensity; // slider, 0.0, 1.0, 0.1, Intensity
    float peak; // slider, 0.0, 1.0, 0.40, Peak
    float rolloff; // slider, 0.01, 1.0, 0.40, Rolloff
    float grainSize; // slider, 0.5, 2.0, 0.75, Grain Size
    float coarseMix; // slider, 0.0, 1.0, 0.40, Coarse Mix
    float blur; // slider, 0.0, 1.0, 0.50, Blur
    float chroma; // slider, 0.0, 0.2, 0.05, Chroma
    float softness; // slider, 0.0, 2.0, 0.5, Softness
    float time; // input, 0.0, Time
} PostUniforms;

static inline float gridHash(float2 cell, float seed)
{
    float2 seededCell = cell + float2(seed * 13.7f, seed * 31.1f);
    float3 hashPosition = fract(float3(seededCell.x, seededCell.y, seededCell.x) * float3(0.1031f, 0.1030f, 0.0973f));
    hashPosition += dot(hashPosition, hashPosition.yzx + 33.33f);
    return fract((hashPosition.x + hashPosition.y) * hashPosition.z);
}

static inline float pixelHash(float2 pixelPosition, float seed)
{
    float2 seededPixel = floor(pixelPosition) + float2(seed * 13.7f, seed * 31.1f);
    float3 hashPosition = fract(float3(seededPixel.x, seededPixel.y, seededPixel.x) * float3(0.1031f, 0.1030f, 0.0973f));
    hashPosition += dot(hashPosition, hashPosition.yzx + 33.33f);
    return fract((hashPosition.x + hashPosition.y) * hashPosition.z) * 2.0f - 1.0f;
}

static inline float quinticSmoothstep(float value)
{
    return value * value * value * (value * (value * 6.0f - 15.0f) + 10.0f);
}

static inline float2 quinticSmoothstep(float2 value)
{
    return float2(quinticSmoothstep(value.x), quinticSmoothstep(value.y));
}

static inline float valueNoise(float2 pixelPosition, float grainSize, float seed)
{
    float2 position = pixelPosition / max(grainSize, 0.001f);
    float2 cell = floor(position);
    float2 fraction = quinticSmoothstep(fract(position));

    float bottomLeft = gridHash(cell + float2(0.0f, 0.0f), seed);
    float bottomRight = gridHash(cell + float2(1.0f, 0.0f), seed);
    float topLeft = gridHash(cell + float2(0.0f, 1.0f), seed);
    float topRight = gridHash(cell + float2(1.0f, 1.0f), seed);

    return mix(mix(bottomLeft, bottomRight, fraction.x), mix(topLeft, topRight, fraction.x), fraction.y) * 2.0f - 1.0f;
}

static inline float fineGrain(float2 pixelPosition, float grainSize, float seed, float blur)
{
    float valueNoiseSample = valueNoise(pixelPosition, grainSize, seed);

    float center = pixelHash(pixelPosition, seed) * 2.0f;
    float right = pixelHash(pixelPosition + float2(1.0f, 0.0f), seed);
    float left = pixelHash(pixelPosition + float2(-1.0f, 0.0f), seed);
    float top = pixelHash(pixelPosition + float2(0.0f, 1.0f), seed);
    float bottom = pixelHash(pixelPosition + float2(0.0f, -1.0f), seed);
    float pixelNoise = (center + right + left + top + bottom) / 6.0f;

    return mix(valueNoiseSample, pixelNoise, clamp(blur, 0.0f, 1.0f));
}

static inline float blurredNoise(float2 pixelPosition, float grainSize, float seed, float blur)
{
    float radius = blur * grainSize * 0.6f;

    float center = valueNoise(pixelPosition, grainSize, seed) * 2.0f;
    float right = valueNoise(pixelPosition + float2(radius, 0.0f), grainSize, seed);
    float left = valueNoise(pixelPosition + float2(-radius, 0.0f), grainSize, seed);
    float top = valueNoise(pixelPosition + float2(0.0f, radius), grainSize, seed);
    float bottom = valueNoise(pixelPosition + float2(0.0f, -radius), grainSize, seed);

    return (center + right + left + top + bottom) / 6.0f;
}

static inline float lumaWeight(float luma, constant PostUniforms &uniforms)
{
    float rolloff = (luma > uniforms.peak) ? uniforms.rolloff * 0.35f : uniforms.rolloff;
    float distanceFromPeak = (luma - uniforms.peak) / max(rolloff, 0.001f);
    float bell = exp(-0.5f * distanceFromPeak * distanceFromPeak);
    float shadow = min(pow(luma / max(uniforms.peak, 0.001f), 0.18f), 1.0f) * smoothstep(0.0f, 0.03f, luma);

    return bell * shadow;
}

static inline float grainSample(float2 pixelPosition, float seed, constant PostUniforms &uniforms)
{
    float grainSize = max(uniforms.grainSize, 0.001f);
    float fine = fineGrain(pixelPosition, grainSize, seed, uniforms.blur);
    float coarse = blurredNoise(pixelPosition, grainSize * 1.5f, seed + 17.3f, uniforms.blur);

    return mix(fine, coarse, clamp(uniforms.coarseMix, 0.0f, 1.0f));
}

fragment half4 postFragment(VertexData in [[stage_in]],
                            constant PostUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
                            texture2d<half, access::sample> renderTex [[texture(FragmentTextureCustom0)]])
{
    float2 resolution = float2(renderTex.get_width(), renderTex.get_height());
    float2 pixelPosition = in.texcoord * resolution;
    float grainSize = max(uniforms.grainSize, 0.001f);
    float seed = uniforms.time;

    float grain = 0.0f;
    if (uniforms.softness < 0.001f) {
        grain = grainSample(pixelPosition, seed, uniforms);
    } else {
        float radius = uniforms.softness * grainSize;
        grain  = grainSample(pixelPosition, seed, uniforms) * 0.238f;
        grain += grainSample(pixelPosition + float2(radius, 0.0f), seed, uniforms) * 0.190f;
        grain += grainSample(pixelPosition + float2(-radius, 0.0f), seed, uniforms) * 0.190f;
        grain += grainSample(pixelPosition + float2(0.0f, radius), seed, uniforms) * 0.190f;
        grain += grainSample(pixelPosition + float2(0.0f, -radius), seed, uniforms) * 0.190f;
    }

    half4 sampledColor = SAMPLER_FNC(renderTex, in.texcoord);
    float3 color = float3(sampledColor.rgb);

    float luma = dot(color, float3(0.2126f, 0.7152f, 0.0722f));
    float weight = lumaWeight(luma, uniforms);
    color += float3(uniforms.intensity * weight * grain);

    if (uniforms.chroma > 0.0f) {
        float chromaGrainSize = grainSize * 1.8f;
        float redGrain = fineGrain(pixelPosition, chromaGrainSize, seed + 31.7f, uniforms.blur);
        float blueGrain = fineGrain(pixelPosition, chromaGrainSize, seed + 57.2f, uniforms.blur);
        float chromaWeight = uniforms.intensity * uniforms.chroma * weight;

        color.r += chromaWeight * redGrain;
        color.b += chromaWeight * blueGrain;
    }

    color = max(color, float3(0.0f));

    return half4(half3(color), sampledColor.a);
}
