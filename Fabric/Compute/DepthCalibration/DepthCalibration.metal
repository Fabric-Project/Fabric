//
//  DepthCalibration.metal
//  Fabric
//

#include <metal_stdlib>
using namespace metal;

// Mirrors DepthCalibrationNode's RemapUniforms exactly.
struct DepthCalibrationRemapUniforms
{
    float scale;
    float offset;
    float near;
    float far;
};

/// Gathers one relative-depth texel per calibration point into a small
/// shared buffer, for a CPU-side scale/offset least-squares fit against the
/// caller's known metric depths at those same points. `pixelPoints` are
/// already in texel space (converted from unit coordinates on the CPU before
/// encoding), one float2 per thread.
kernel void depthCalibrationSampleRelativeDepth(
    texture2d<float, access::read> relativeDepth [[texture(0)]],
    constant float2 *pixelPoints [[buffer(0)]],
    device float *sampledValues [[buffer(1)]],
    uint id [[thread_position_in_grid]]
)
{
    float2 point = pixelPoints[id];
    uint2 texel = uint2(
        clamp(point.x, 0.0, float(relativeDepth.get_width() - 1)),
        clamp(point.y, 0.0, float(relativeDepth.get_height() - 1))
    );
    sampledValues[id] = relativeDepth.read(texel).r;
}

/// Remaps ZipDepth's affine-invariant relative depth into Satin's reverse-Z
/// NDC depth: metricDepth = scale * relative + offset, then
/// ndc = near * (far - metricDepth) / (metricDepth * (far - near)) --
/// derived from Satin's own perspectiveMatrixf (SatinCore/Transforms.mm),
/// not a generic textbook formula, so it matches what Satin's rasterizer
/// actually produces for real geometry at the same near/far.
kernel void depthCalibrationRemapToSceneDepth(
    texture2d<float, access::read> relativeDepth [[texture(0)]],
    texture2d<float, access::write> sceneDepth [[texture(1)]],
    constant DepthCalibrationRemapUniforms &uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
)
{
    float relative = relativeDepth.read(gid).r;
    float metricDepth = uniforms.scale * relative + uniforms.offset;
    // Guard the divide below: a metricDepth at or behind near is invalid input,
    // not a value the affine fit should ever legitimately produce.
    metricDepth = max(metricDepth, uniforms.near);

    float ndcDepth = uniforms.near * (uniforms.far - metricDepth)
        / (metricDepth * (uniforms.far - uniforms.near));

    sceneDepth.write(float4(saturate(ndcDepth), 0.0, 0.0, 1.0), gid);
}
