//
//  LucasKanadeFlow.metal
//  Fabric
//
//  Pyramidal Lucas-Kanade optical flow — inverse-additive Gauss-Newton formulation.
//  Reference: CShade cFlow.fx / cMotionEstimation.fxh (github.com/papadanku/CShade)
//
//  Output flow is stored in RG16Float textures as signed UV-space displacements:
//    R = horizontal displacement, positive = rightward
//    G = vertical displacement,   positive = downward (texture-space, +V down)
//  Values are clamped to [-1, 1] (±1 = full image width/height per frame).
//
//  This matches Satin's velocity buffer convention and works directly with
//  GradientFlowOffset.metal and PostProcessMotionBlurNode.
//
//  Pyramid strategy: preprocess each frame into a perceptual RGB feature texture,
//  generate its mip chain with a blit encoder, then sample explicit mip levels.
//

#include <metal_stdlib>
using namespace metal;

#define SAMPLER_TYPE  texture2d<half>
#define SAMPLER_PRECISION half4
#include "../../lygia/sampler.msl"
#include "../../lygia/color/luminance.msl"

struct LKUniforms {
    uint2 resolution;
    uint  pyramidLevel;
    uint  useInitFlow;   // 0 at coarsest level (zero initial guess); 1 uses coarseFlow
};

// ─── Pass 1: perceptual RGB feature pyramid base ──────────────────────────
//
// Preserve chromatic gradients instead of collapsing dark, saturated images to
// low-precision luma. Metal's blit mip generator builds the remaining levels.

kernel void lk_preprocess(
    texture2d<half, access::sample> src [[texture(0)]],
    texture2d<half, access::write>  dst [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    float2 uv = (float2(gid) + 0.5) / float2(dst.get_width(), dst.get_height());
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float3 linearColor = max(float3(src.sample(s, uv).rgb), 0.0f);
    float3 perceptualColor = log2(1.0f + 15.0f * linearColor) * 0.25f;
    float sum = perceptualColor.r + perceptualColor.g + perceptualColor.b;
    float3 ratio = sum > 1e-6f ? perceptualColor / sum : float3(1.0f / 3.0f);
    float maximumRatio = max(ratio.r, max(ratio.g, ratio.b));
    float maximumColor = max(perceptualColor.r, max(perceptualColor.g, perceptualColor.b));
    float2 chroma = maximumRatio > 1e-6f ? ratio.rg / maximumRatio : float2(1.0f);
    dst.write(half4(half2(chroma), half(maximumColor), 1.0h), gid);
}

// ─── Pass 2: LK at one pyramid level ──────────────────────────────────────
//
// Tile = 16×16, halo = 2. Shared region = 20×20. The LK window is 3×3,
// matching the reference implementation; the second halo texel supplies the
// template-gradient samples at the window boundary.
//
// The pyramid textures are full-resolution mipmapped textures. pyramidLevel
// selects the level corresponding to the output flow resolution.

kernel void lk_flow_level(
    texture2d<half, access::sample> prevPyramid [[texture(0)]],
    texture2d<half, access::sample> currPyramid [[texture(1)]],
    texture2d<half, access::sample> coarseFlow  [[texture(2)]],
    texture2d<half, access::write>  outFlow     [[texture(3)]],
    constant LKUniforms& u                      [[buffer(0)]],
    uint2 gid  [[thread_position_in_grid]],
    uint2 lid  [[thread_position_in_threadgroup]],
    uint2 tgid [[threadgroup_position_in_grid]])
{
    const uint W = outFlow.get_width();
    const uint H = outFlow.get_height();

    constexpr int TW   = 16;
    constexpr int TH   = 16;
    constexpr int HALO = 2;
    constexpr int SW   = TW + 2 * HALO;   // 20

    threadgroup half4 shPrev[20 * 20];

    constexpr sampler s(filter::linear, address::clamp_to_edge);

    // All threads load shPrev before the bounds check so edge threadgroups
    // (from dispatchThreadgroups) cooperatively fill the shared array.
    int2  tileOrigin = int2(tgid) * int2(TW, TH) - int2(HALO, HALO);
    uint  tid1D      = lid.y * TW + lid.x;
    float invW       = 1.0f / float(W);
    float invH       = 1.0f / float(H);

    for (uint i = tid1D; i < 20u * 20u; i += TW * TH) {
        int sx = int(i % 20);
        int sy = int(i / 20);
        int2 sourceCoordinate = clamp(tileOrigin + int2(sx, sy),
                                      int2(0),
                                      int2(int(W) - 1, int(H) - 1));
        shPrev[i] = prevPyramid.read(uint2(sourceCoordinate), u.pyramidLevel);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    if (gid.x >= W || gid.y >= H) return;

    float2 uv = (float2(gid) + 0.5) * float2(invW, invH);
    float2 v0 = (u.useInitFlow != 0u) ? float2(coarseFlow.sample(s, uv).rg) : float2(0);

    int   cx         = int(lid.x) + HALO;
    int   cy         = int(lid.y) + HALO;
    float2 invSize = float2(invW, invH);
    float Ixx = 0, Iyy = 0, Ixy = 0, Ixt = 0, Iyt = 0;

    for (int wy = -1; wy <= 1; wy++) {
        for (int wx = -1; wx <= 1; wx++) {
            int   nx = cx + wx;
            int   ny = cy + wy;
            float3 T = float3(shPrev[ny * SW + nx].rgb);

            float2 wUV = uv + v0 + float2(wx, wy) * invSize;
            float3 C = float3(currPyramid.sample(s, wUV, level(float(u.pyramidLevel))).rgb);

            // Inverse-additive LK uses the template gradient. It is already in
            // tile memory, reducing this loop from five texture samples to one.
            float3 Ix = 0.5f * (float3(shPrev[ny * SW + nx + 1].rgb)
                              - float3(shPrev[ny * SW + nx - 1].rgb));
            float3 Iy = 0.5f * (float3(shPrev[(ny + 1) * SW + nx].rgb)
                              - float3(shPrev[(ny - 1) * SW + nx].rgb));
            float3 It = C - T;

            Ixx += dot(Ix, Ix);
            Iyy += dot(Iy, Iy);
            Ixy += dot(Ix, Iy);
            Ixt += dot(Ix, It);
            Iyt += dot(Iy, It);
        }
    }

    // Two-stage conditioning check: skip the solve in flat/near-singular regions
    // to avoid dividing by a near-zero det and clamping the result to ±1 speckle.
    float trace = Ixx + Iyy;
    float det   = Ixx * Iyy - Ixy * Ixy;
    float2 dv   = float2(0);
    if (trace > 1e-4f && abs(det) > trace * trace * 1e-2f) {
        dv.x = (-Ixt * Iyy + Iyt * Ixy) / det;
        dv.y = (-Iyt * Ixx + Ixt * Ixy) / det;
        if (dot(dv, dv) > 4.0f) dv = float2(0);  // discard physically unreasonable solves
    }

    // The normal-equation solution is in pixels. Convert it before combining
    // it with the normalized UV-space pyramid estimate.
    float2 flow = clamp(v0 + dv * invSize, -1.0f, 1.0f);
    outFlow.write(half4(half2(flow), 0, 1), gid);
}

// ─── Pass 3: component-wise median outlier rejection ─────────────────────

inline void lk_compare_swap(thread half2& first, thread half2& second)
{
    half2 lower = min(first, second);
    half2 upper = max(first, second);
    first = lower;
    second = upper;
}

kernel void lk_median_filter(
    texture2d<half, access::sample> source [[texture(0)]],
    texture2d<half, access::write> destination [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    const uint width = destination.get_width();
    const uint height = destination.get_height();
    if (gid.x >= width || gid.y >= height) return;

    constexpr sampler sampleLinear(filter::linear, address::clamp_to_edge);
    float2 inverseSize = 1.0f / float2(width, height);
    float2 uv = (float2(gid) + 0.5f) * inverseSize;
    half2 values[9];

    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            int index = (y + 1) * 3 + x + 1;
            values[index] = source.sample(sampleLinear,
                                          uv + float2(x, y) * inverseSize).rg;
        }
    }

    // Odd-even transposition is a fixed sorting network here: no data-dependent
    // branches, and both flow components are sorted in parallel as half2 values.
    #pragma unroll
    for (int phase = 0; phase < 9; phase++) {
        int firstIndex = phase & 1;
        #pragma unroll
        for (int index = firstIndex; index < 8; index += 2) {
            lk_compare_swap(values[index], values[index + 1]);
        }
    }

    destination.write(half4(values[4], 0.0h, 1.0h), gid);
}

// ─── Pass 4: Joint bilateral upsample (luma-guided, side-window) ──────────
//
// fineLuma should be at the same resolution as outFlow (the Swift node passes
// the per-level luma from the explicit pyramid at the correct output resolution).

inline void lk_consider_upsample_candidate(half2 flowSum,
                                           half guideSum,
                                           half inverseCount,
                                           half guideCenter,
                                           thread half2& bestFlow,
                                           thread half& bestError)
{
    half candidateError = abs(guideSum * inverseCount - guideCenter);
    if (candidateError < bestError) {
        bestError = candidateError;
        bestFlow = flowSum * inverseCount;
    }
}

kernel void lk_bilateral_upsample(
    texture2d<half, access::sample> coarseFlow  [[texture(0)]],
    texture2d<half, access::sample> fineLuma    [[texture(1)]],
    texture2d<half, access::write>  outFlow     [[texture(2)]],
    uint2 gid [[thread_position_in_grid]])
{
    const uint W = outFlow.get_width();
    const uint H = outFlow.get_height();
    if (gid.x >= W || gid.y >= H) return;

    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv  = (float2(gid) + 0.5) / float2(W, H);
    float2 dx = float2(1.0f / float(coarseFlow.get_width()), 0);
    float2 dy = float2(0, 1.0f / float(coarseFlow.get_height()));

    half2 f[9];
    half  g[9];
    for (int ky = -1; ky <= 1; ky++) {
        for (int kx = -1; kx <= 1; kx++) {
            int i       = (ky + 1) * 3 + (kx + 1);
            float2 off  = float(kx) * dx + float(ky) * dy;
            f[i]        = coarseFlow.sample(s, uv + off).rg;
            g[i]        = fineLuma.sample(s,   uv + off).r;
        }
    }
    half gCenter = g[4];

    half2 bestFlow  = f[4];
    half  bestError = half(1e9f);

    half2 flowTopLeft = f[0] + f[1] + f[3] + f[4];
    half2 flowTopRight = f[1] + f[2] + f[4] + f[5];
    half2 flowBottomLeft = f[3] + f[4] + f[6] + f[7];
    half2 flowBottomRight = f[4] + f[5] + f[7] + f[8];
    half guideTopLeft = g[0] + g[1] + g[3] + g[4];
    half guideTopRight = g[1] + g[2] + g[4] + g[5];
    half guideBottomLeft = g[3] + g[4] + g[6] + g[7];
    half guideBottomRight = g[4] + g[5] + g[7] + g[8];

    constexpr half inverseFour = half(0.25h);
    constexpr half inverseSix = half(1.0h / 6.0h);
    lk_consider_upsample_candidate(flowTopLeft, guideTopLeft, inverseFour,
                                   gCenter, bestFlow, bestError);
    lk_consider_upsample_candidate(flowTopRight, guideTopRight, inverseFour,
                                   gCenter, bestFlow, bestError);
    lk_consider_upsample_candidate(flowBottomLeft, guideBottomLeft, inverseFour,
                                   gCenter, bestFlow, bestError);
    lk_consider_upsample_candidate(flowBottomRight, guideBottomRight, inverseFour,
                                   gCenter, bestFlow, bestError);

    half2 flowTop = f[0] + f[1] + f[2] + f[3] + f[4] + f[5];
    half2 flowBottom = f[3] + f[4] + f[5] + f[6] + f[7] + f[8];
    half2 flowLeft = f[0] + f[1] + f[3] + f[4] + f[6] + f[7];
    half2 flowRight = f[1] + f[2] + f[4] + f[5] + f[7] + f[8];
    half guideTop = g[0] + g[1] + g[2] + g[3] + g[4] + g[5];
    half guideBottom = g[3] + g[4] + g[5] + g[6] + g[7] + g[8];
    half guideLeft = g[0] + g[1] + g[3] + g[4] + g[6] + g[7];
    half guideRight = g[1] + g[2] + g[4] + g[5] + g[7] + g[8];

    lk_consider_upsample_candidate(flowTop, guideTop, inverseSix,
                                   gCenter, bestFlow, bestError);
    lk_consider_upsample_candidate(flowBottom, guideBottom, inverseSix,
                                   gCenter, bestFlow, bestError);
    lk_consider_upsample_candidate(flowLeft, guideLeft, inverseSix,
                                   gCenter, bestFlow, bestError);
    lk_consider_upsample_candidate(flowRight, guideRight, inverseSix,
                                   gCenter, bestFlow, bestError);

    outFlow.write(half4(bestFlow, 0, 1), gid);
}

// ─── Pass 5: temporal flow smoothing ──────────────────────────────────────

kernel void lk_temporal_smooth(
    texture2d<half, access::sample> currentFlow [[texture(0)]],
    texture2d<half, access::sample> previousFlow [[texture(1)]],
    texture2d<half, access::write> outputFlow [[texture(2)]],
    constant float& previousFlowWeight [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    const uint width = outputFlow.get_width();
    const uint height = outputFlow.get_height();
    if (gid.x >= width || gid.y >= height) return;

    constexpr sampler sampleLinear(filter::linear, address::clamp_to_edge);
    float2 uv = (float2(gid) + 0.5f) / float2(width, height);
    float2 current = float2(currentFlow.sample(sampleLinear, uv).rg);
    float2 previous = float2(previousFlow.sample(sampleLinear, uv).rg);
    float2 smoothed = mix(current, previous, saturate(previousFlowWeight));
    outputFlow.write(half4(half2(smoothed), 0.0h, 1.0h), gid);
}
