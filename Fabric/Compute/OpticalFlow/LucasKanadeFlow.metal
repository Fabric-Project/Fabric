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
// Tile = 16×16, halo = 3. Shared region = 22×22 = 484 halfs = 968 B.
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
    constexpr int HALO = 3;
    constexpr int SW   = TW + 2 * HALO;   // 22

    threadgroup half4 shPrev[22 * 22];

    constexpr sampler s(filter::linear, address::clamp_to_edge);

    // All threads load shPrev before the bounds check so edge threadgroups
    // (from dispatchThreadgroups) cooperatively fill the shared array.
    int2  tileOrigin = int2(tgid) * int2(TW, TH) - int2(HALO, HALO);
    uint  tid1D      = lid.y * TW + lid.x;
    float invW       = 1.0f / float(W);
    float invH       = 1.0f / float(H);

    for (uint i = tid1D; i < 22u * 22u; i += TW * TH) {
        int   sx   = int(i % 22);
        int   sy   = int(i / 22);
        float2 sUV = (float2(tileOrigin + int2(sx, sy)) + 0.5) * float2(invW, invH);
        shPrev[i] = prevPyramid.sample(s, sUV, level(float(u.pyramidLevel)));
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    if (gid.x >= W || gid.y >= H) return;

    float2 uv = (float2(gid) + 0.5) * float2(invW, invH);
    float2 v0 = (u.useInitFlow != 0u) ? float2(coarseFlow.sample(s, uv).rg) : float2(0);

    int   cx         = int(lid.x) + HALO;
    int   cy         = int(lid.y) + HALO;
    float2 invSize = float2(invW, invH);
    float Ixx = 0, Iyy = 0, Ixy = 0, Ixt = 0, Iyt = 0;

    for (int wy = -2; wy <= 2; wy++) {
        for (int wx = -2; wx <= 2; wx++) {
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
    float horizontal[9];
    float vertical[9];

    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            int index = (y + 1) * 3 + x + 1;
            float2 flow = float2(source.sample(sampleLinear,
                                               uv + float2(x, y) * inverseSize).rg);
            horizontal[index] = flow.x;
            vertical[index] = flow.y;
        }
    }

    for (int index = 1; index < 9; index++) {
        float horizontalValue = horizontal[index];
        float verticalValue = vertical[index];
        int insertionIndex = index - 1;
        while (insertionIndex >= 0 && horizontal[insertionIndex] > horizontalValue) {
            horizontal[insertionIndex + 1] = horizontal[insertionIndex];
            insertionIndex--;
        }
        horizontal[insertionIndex + 1] = horizontalValue;

        insertionIndex = index - 1;
        while (insertionIndex >= 0 && vertical[insertionIndex] > verticalValue) {
            vertical[insertionIndex + 1] = vertical[insertionIndex];
            insertionIndex--;
        }
        vertical[insertionIndex + 1] = verticalValue;
    }

    destination.write(half4(half(horizontal[4]), half(vertical[4]), 0.0h, 1.0h), gid);
}

// ─── Pass 4: Joint bilateral upsample (luma-guided, side-window) ──────────
//
// fineLuma should be at the same resolution as outFlow (the Swift node passes
// the per-level luma from the explicit pyramid at the correct output resolution).

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

    for (int w = 0; w < 8; w++) {
        half2 sumF = half2(0);
        half  sumG = half(0);
        int   cnt  = 0;

        for (int ky = -1; ky <= 1; ky++) {
            for (int kx = -1; kx <= 1; kx++) {
                bool inside;
                switch (w) {
                    case 0: inside = (kx <= 0 && ky <= 0); break;
                    case 1: inside = (kx >= 0 && ky <= 0); break;
                    case 2: inside = (kx <= 0 && ky >= 0); break;
                    case 3: inside = (kx >= 0 && ky >= 0); break;
                    case 4: inside = (ky <= 0);             break;
                    case 5: inside = (ky >= 0);             break;
                    case 6: inside = (kx <= 0);             break;
                    case 7: inside = (kx >= 0);             break;
                    default: inside = false;                 break;
                }
                if (inside) {
                    int i = (ky + 1) * 3 + (kx + 1);
                    sumF += f[i];
                    sumG += g[i];
                    cnt++;
                }
            }
        }

        half meanG = sumG / half(cnt);
        half err   = abs(meanG - gCenter);
        if (err < bestError) {
            bestError = err;
            bestFlow  = sumF / half(cnt);
        }
    }

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
