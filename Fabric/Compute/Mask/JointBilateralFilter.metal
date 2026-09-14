//
//  JointBilateralFilter.metal
//  Fabric
//

#include <metal_stdlib>
using namespace metal;

// Standard cross/joint bilateral filter: signalTexture is smoothed using
// weights derived from BOTH spatial distance and how similar guideTexture's
// luma is at each sample -- flat regions blur normally, but any edge in the
// guide image (not the signal) stops the blur from crossing it. This is
// what recovers sharp silhouette edges from a low-resolution mask that was
// only bilinearly upsampled (MediaPipe's own segmentation solutions
// explicitly recommend this exact technique for that exact problem).
//
// Assumes signalTexture and guideTexture share the same pixel dimensions as
// outputTexture -- the caller's job to guarantee (both are already at full
// output resolution in every use this node was built for).
struct JointBilateralFilterUniforms {
    int radius;          // kernel half-width in pixels
    float spatialSigma;  // spatial falloff -- larger blurs further
    float rangeSigma;    // guide-luma-difference tolerance treated as "still the same surface"
};

kernel void jointBilateralFilter(
    texture2d<float, access::sample> signalTexture [[texture(0)]],
    texture2d<float, access::sample> guideTexture [[texture(1)]],
    texture2d<float, access::write> outputTexture [[texture(2)]],
    constant JointBilateralFilterUniforms &uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    const uint width = outputTexture.get_width();
    const uint height = outputTexture.get_height();
    if (gid.x >= width || gid.y >= height) { return; }

    constexpr sampler pixelSampler(coord::pixel, address::clamp_to_edge, filter::linear);
    constexpr float3 lumaWeights = float3(0.2126f, 0.7152f, 0.0722f);

    const float2 centerCoord = float2(gid) + 0.5f;
    const float centerGuideLuma = dot(guideTexture.sample(pixelSampler, centerCoord).rgb, lumaWeights);

    const float twoSpatialSigmaSq = 2.0f * uniforms.spatialSigma * uniforms.spatialSigma;
    const float twoRangeSigmaSq = 2.0f * uniforms.rangeSigma * uniforms.rangeSigma;

    float4 accumulatedSignal = float4(0.0f);
    float accumulatedWeight = 0.0f;

    for (int dy = -uniforms.radius; dy <= uniforms.radius; dy++)
    {
        for (int dx = -uniforms.radius; dx <= uniforms.radius; dx++)
        {
            const float2 sampleCoord = centerCoord + float2(dx, dy);

            const float spatialDistanceSq = float(dx * dx + dy * dy);
            const float spatialWeight = exp(-spatialDistanceSq / twoSpatialSigmaSq);

            const float4 sampleSignal = signalTexture.sample(pixelSampler, sampleCoord);
            const float sampleGuideLuma = dot(guideTexture.sample(pixelSampler, sampleCoord).rgb, lumaWeights);
            const float rangeDelta = sampleGuideLuma - centerGuideLuma;
            const float rangeWeight = exp(-(rangeDelta * rangeDelta) / twoRangeSigmaSq);

            const float weight = spatialWeight * rangeWeight;
            accumulatedSignal += sampleSignal * weight;
            accumulatedWeight += weight;
        }
    }

    const float4 result = accumulatedWeight > 0.0f
        ? (accumulatedSignal / accumulatedWeight)
        : signalTexture.sample(pixelSampler, centerCoord);

    outputTexture.write(result, gid);
}
