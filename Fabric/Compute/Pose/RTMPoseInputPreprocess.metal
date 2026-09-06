//
//  RTMPoseInputPreprocess.metal
//  Fabric
//

#include <metal_stdlib>
#include "../../Shaders/FabricImageTextureTransform.metal"

using namespace metal;

struct RTMPoseInputUniforms {
    float2 regionOrigin;
    float2 regionSize;
    float4x4 textureTransform;
    uint2 outputSize;
};

static float4 samplePresentationRegion(
    texture2d<float, access::sample> sourceTexture,
    constant RTMPoseInputUniforms &uniforms,
    uint2 position)
{
    constexpr sampler sourceSampler(
        coord::normalized,
        address::clamp_to_edge,
        min_filter::linear,
        mag_filter::linear
    );

    const float2 outputCoordinate = (float2(position) + 0.5f) / float2(uniforms.outputSize);
    const float2 presentationCoordinate = uniforms.regionOrigin + outputCoordinate * uniforms.regionSize;
    const float2 storedCoordinate = fabricTextureCoordinate(uniforms.textureTransform, presentationCoordinate);
    return sourceTexture.sample(sourceSampler, storedCoordinate);
}

kernel void cropScaleAndNormalizePlanarRGB(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    device float *destination [[buffer(0)]],
    constant RTMPoseInputUniforms &uniforms [[buffer(1)]],
    uint2 position [[thread_position_in_grid]])
{
    if (position.x >= uniforms.outputSize.x || position.y >= uniforms.outputSize.y) {
        return;
    }

    const float3 color = samplePresentationRegion(sourceTexture, uniforms, position).rgb * 255.0f;
    constexpr float3 mean = float3(123.675f, 116.28f, 103.53f);
    constexpr float3 standardDeviation = float3(58.395f, 57.12f, 57.375f);
    const float3 normalizedColor = (color - mean) / standardDeviation;

    const uint pixelIndex = position.y * uniforms.outputSize.x + position.x;
    const uint planeSize = uniforms.outputSize.x * uniforms.outputSize.y;
    destination[pixelIndex] = normalizedColor.r;
    destination[planeSize + pixelIndex] = normalizedColor.g;
    destination[2 * planeSize + pixelIndex] = normalizedColor.b;
}
