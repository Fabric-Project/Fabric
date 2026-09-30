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
// Uses one bilinear sample at each output texel center. This deliberately
// matches EfficientTAMMaskProjector's half-pixel-centered bilinear projection,
// so a projected model mask and its regression Guide stay on the same grid.
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
    const float2 canonicalCoord = (float2(gid) + 0.5f) / outputSize;
    const float2 storedCoord = (uniforms.textureTransform * float4(canonicalCoord, 0.0f, 1.0f)).xy;
    outputTexture.write(sourceTexture.sample(linearSampler, storedCoord), gid);
}
