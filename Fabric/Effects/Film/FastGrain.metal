
//
//  FastGrain.metal
//  Fabric
//
// description: Adds low-cost luminance-masked film grain

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"

typedef struct {
    float amount; // slider, 0.0, 1.0, 0.05, Amount
    float grainSize; // slider, 0.5, 5.0, 2.0, Grain Size
    float colorSaturation; // slider, 0.0, 1.0, 0.2, Color Saturation
    float time; // input, 0.0, Time
} PostUniforms;

static inline float fastGrainHash(float2 grainCell, float seed)
{
    float2 seededCell = grainCell + float2(seed * 113.1f, seed * 179.3f);
    float3 hashPosition = fract(float3(seededCell.x, seededCell.y, seededCell.x) * float3(0.1031f, 0.1030f, 0.0973f));
    hashPosition += dot(hashPosition, hashPosition.yzx + 33.33f);
    float hash = fract((hashPosition.x + hashPosition.y) * hashPosition.z);

    return hash * 2.0f - 1.0f;
}

static inline float3 fastGrainNoise(float2 grainCell, float seed, float amount, float colorSaturation)
{
    float red = fastGrainHash(grainCell, seed);
    float green = fastGrainHash(grainCell + float2(17.0f, 29.0f), seed + 0.37f);
    float blue = fastGrainHash(grainCell + float2(43.0f, 11.0f), seed + 0.73f);
    float3 colorNoise = float3(red, green, blue) * amount;
    float luma = dot(colorNoise, float3(0.299f, 0.587f, 0.114f));

    return mix(float3(luma), colorNoise, clamp(colorSaturation, 0.0f, 1.0f));
}

fragment half4 postFragment(VertexData in [[stage_in]],
                            constant PostUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
                            texture2d<half, access::sample> renderTex [[texture(FragmentTextureCustom0)]])
{
    half4 sampledColor = SAMPLER_FNC(renderTex, in.texcoord);
    float3 sceneColor = float3(sampledColor.rgb);
    float2 textureSize = float2(renderTex.get_width(), renderTex.get_height());
    float grainSize = max(uniforms.grainSize, 0.5f);
    float2 grainCell = floor(in.texcoord * textureSize / grainSize);

    float3 grainNoise = fastGrainNoise(grainCell, uniforms.time, uniforms.amount, uniforms.colorSaturation);
    float sceneLuma = clamp(dot(sceneColor, float3(0.299f, 0.587f, 0.114f)), 0.0f, 1.0f);
    float luminanceMask = 4.0f * sceneLuma * (1.0f - sceneLuma);
    sceneColor += grainNoise * luminanceMask;

    return half4(half3(sceneColor), sampledColor.a);
}
