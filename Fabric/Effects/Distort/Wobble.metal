#include <metal_stdlib>
using namespace metal;

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"

// Derived from Metal's built-in constants
constant float C_PI    = M_PI_F;
constant float C_2PI   = 2.0f * M_PI_F;
constant float C_2PI_I = 1.0f / C_2PI;
constant float C_PI_2  = M_PI_2_F;

// Uniforms -> Fabric UI sliders
typedef struct {
    float  radius; // slider, 0.0, 5.0, 0.0, Radius
    float2 freq;   // xypad, 0.0, 20.0, 5.0, Frequency
    float2 amp;    // xypad, -0.5, 0.5, 0.05, Amplitude
} PostUniforms;

fragment half4 postFragment( VertexData                        in        [[stage_in]],
                             constant PostUniforms            &uniforms  [[buffer( FragmentBufferMaterialUniforms )]],
                             texture2d<half, access::sample>   renderTex [[texture( FragmentTextureCustom0 )]] )
{
    float2 uv = in.texcoord; // normalized [0, 1]

    float2 perturb = float2(0.0);
    float  rad;

    // --- X perturbation -----------------------------------------------------
    rad = (uv.x + uv.y - 1.0f + uniforms.radius) * uniforms.freq.x;

    // Wrap to [-2π, 2π] via fractional 0..1 then scale
    rad *= C_2PI_I;
    rad = fract(rad);
    rad *= C_2PI;

    // Center in [-π, π]
    if (rad >  C_PI) rad -= C_2PI;
    if (rad < -C_PI) rad += C_2PI;

    // Center in [-π/2, π/2]
    if (rad >  C_PI_2) rad =  C_PI - rad;
    if (rad < -C_PI_2) rad = -C_PI - rad;

    // Approximate sin(rad) with Taylor: sin(x) ≈ x - x^3/6
    perturb.x = (rad - (rad * rad * rad / 6.0f)) * uniforms.amp.x;

    // --- Y perturbation -----------------------------------------------------
    rad = (uv.x - uv.y + uniforms.radius) * uniforms.freq.y;

    // Wrap to [-2π, 2π]
    rad *= C_2PI_I;
    rad = fract(rad);
    rad *= C_2PI;

    // Center in [-π, π]
    if (rad >  C_PI) rad -= C_2PI;
    if (rad < -C_PI) rad += C_2PI;

    // Center in [-π/2, π/2]
    if (rad >  C_PI_2) rad =  C_PI - rad;
    if (rad < -C_PI_2) rad = -C_PI - rad;

    perturb.y = (rad - (rad * rad * rad / 6.0f)) * uniforms.amp.y;

    // Final UV with wobble
    float2 wobbleUV = uv + perturb;
    wobbleUV = clamp(wobbleUV, 0.0f, 1.0f);

    return SAMPLER_FNC(renderTex, wobbleUV);
}
