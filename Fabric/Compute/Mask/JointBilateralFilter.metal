//
//  JointBilateralFilter.metal
//  Fabric
//

#include <metal_stdlib>
using namespace metal;

// Joint bilateral filter / joint bilateral upsampling (Kopf et al. 2007).
//
// The GUIDE defines the output: one output pixel per guide pixel in canonical
// (presentation) orientation, exactly like BaseImageNode sizes and orients its
// output from its first input. The SIGNAL may be any size and orientation --
// typically a small mask -- and is read through its own texture transform.
//
// For each output pixel the filter visits the signal's own texels around the
// point that pixel maps to. Each neighbor contributes its signal value with a
// weight that is the product of
//   - a Gaussian of its distance in SIGNAL pixels, and
//   - a Gaussian of how different the GUIDE's luma is at the neighbor's true
//     position from the guide's luma at the output pixel itself.
// So a sharp edge in the guide stops the blend from crossing it, even where
// the signal only had one texel across that edge. Radius and spatialSigma are
// in signal pixels, which makes the cost independent of the guide's
// resolution. When signal and guide have the same size and no transform this
// is the plain joint bilateral filter.
struct JointBilateralFilterUniforms {
    int radius;                       // kernel half-width in signal pixels
    float spatialSigma;               // spatial falloff in signal pixels
    float rangeSigma;                 // guide-luma tolerance treated as "still the same surface"
    float4x4 guideTransform;          // canonical -> stored guide coordinates
    float4x4 signalTransform;         // canonical -> stored signal coordinates
    float4x4 signalTransformInverse;  // stored signal -> canonical coordinates
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

    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    constexpr sampler nearestSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
    constexpr float3 lumaWeights = float3(0.2126f, 0.7152f, 0.0722f);

    const float2 canonicalCoord = (float2(gid) + 0.5f) / float2(width, height);

    const float2 centerGuideCoord = (uniforms.guideTransform * float4(canonicalCoord, 0.0f, 1.0f)).xy;
    const float centerGuideLuma = dot(guideTexture.sample(linearSampler, centerGuideCoord).rgb, lumaWeights);

    const float2 signalSize = float2(signalTexture.get_width(), signalTexture.get_height());
    const float2 centerSignalCoord = (uniforms.signalTransform * float4(canonicalCoord, 0.0f, 1.0f)).xy;
    const float2 centerSignalPixel = centerSignalCoord * signalSize;
    const float2 anchorTexel = floor(centerSignalPixel);

    const float twoSpatialSigmaSq = 2.0f * uniforms.spatialSigma * uniforms.spatialSigma;
    const float twoRangeSigmaSq = 2.0f * uniforms.rangeSigma * uniforms.rangeSigma;

    float4 accumulatedSignal = float4(0.0f);
    float accumulatedWeight = 0.0f;

    for (int dy = -uniforms.radius; dy <= uniforms.radius; dy++)
    {
        for (int dx = -uniforms.radius; dx <= uniforms.radius; dx++)
        {
            const float2 neighborPixel = anchorTexel + float2(dx, dy) + 0.5f;

            // Distance is measured before clamping; the value and the guide
            // are taken at the clamped texel, i.e. clamp-to-edge.
            const float2 offset = neighborPixel - centerSignalPixel;
            const float spatialWeight = exp(-dot(offset, offset) / twoSpatialSigmaSq);

            const float2 clampedPixel = clamp(neighborPixel, float2(0.5f), signalSize - 0.5f);
            const float2 neighborSignalCoord = clampedPixel / signalSize;
            const float4 sampleSignal = signalTexture.sample(nearestSampler, neighborSignalCoord);

            // Where that signal texel actually sits in the guide.
            const float2 neighborCanonicalCoord = (uniforms.signalTransformInverse * float4(neighborSignalCoord, 0.0f, 1.0f)).xy;
            const float2 neighborGuideCoord = (uniforms.guideTransform * float4(neighborCanonicalCoord, 0.0f, 1.0f)).xy;
            const float sampleGuideLuma = dot(guideTexture.sample(linearSampler, neighborGuideCoord).rgb, lumaWeights);

            const float rangeDelta = sampleGuideLuma - centerGuideLuma;
            const float rangeWeight = exp(-(rangeDelta * rangeDelta) / twoRangeSigmaSq);

            const float weight = spatialWeight * rangeWeight;
            accumulatedSignal += sampleSignal * weight;
            accumulatedWeight += weight;
        }
    }

    const float4 result = accumulatedWeight > 0.0f
        ? (accumulatedSignal / accumulatedWeight)
        : signalTexture.sample(linearSampler, centerSignalCoord);

    outputTexture.write(result, gid);
}
