//
//  CanonicalResample.metal
//  Fabric
//

#include <metal_stdlib>
using namespace metal;

// Resamples an image, through its own texture transform, into a new texture of
// any size in canonical (presentation) orientation. Used where a kernel needs
// its inputs pixel-aligned, such as MPSImageGuidedFilter's low-resolution
// regression stage, which needs the guide at the signal's resolution.
//
// Downscaling averages a grid of taps across each output pixel's footprint
// (up to 8x8), so a large guide shrunk to a small mask is area-averaged
// rather than aliased. At one-to-one it is an exact copy.
struct CanonicalResampleUniforms {
    float4x4 textureTransform;  // canonical -> stored coordinates of the source
};

kernel void resampleToCanonical(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant CanonicalResampleUniforms &uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    const uint width = outputTexture.get_width();
    const uint height = outputTexture.get_height();
    if (gid.x >= width || gid.y >= height) { return; }

    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);

    const float2 outputSize = float2(width, height);
    const float2 sourceSize = float2(sourceTexture.get_width(), sourceTexture.get_height());
    const float2 canonicalCoord = (float2(gid) + 0.5f) / outputSize;

    // How many source texels one output pixel spans along each output axis
    // (w = 0: direction only, no translation).
    const float2 storedStepX = (uniforms.textureTransform * float4(1.0f / outputSize.x, 0.0f, 0.0f, 0.0f)).xy;
    const float2 storedStepY = (uniforms.textureTransform * float4(0.0f, 1.0f / outputSize.y, 0.0f, 0.0f)).xy;
    const int tapsX = clamp(int(ceil(length(storedStepX * sourceSize))), 1, 8);
    const int tapsY = clamp(int(ceil(length(storedStepY * sourceSize))), 1, 8);

    float4 accumulated = float4(0.0f);
    for (int tapY = 0; tapY < tapsY; tapY++)
    {
        for (int tapX = 0; tapX < tapsX; tapX++)
        {
            const float2 tapOffset = (float2((tapX + 0.5f) / tapsX, (tapY + 0.5f) / tapsY) - 0.5f) / outputSize;
            const float2 storedCoord = (uniforms.textureTransform * float4(canonicalCoord + tapOffset, 0.0f, 1.0f)).xy;
            accumulated += sourceTexture.sample(linearSampler, storedCoord);
        }
    }

    outputTexture.write(accumulated / float(tapsX * tapsY), gid);
}
