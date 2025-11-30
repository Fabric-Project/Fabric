#include <metal_stdlib>
using namespace metal;

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>
#define SAMPLER sampler( min_filter::linear, mag_filter::linear, address::mirrored_repeat )

#include "../../lygia/sampler.msl"

// Optional, only if you need it elsewhere
// #include "Library/Repeat.metal"

// Uniforms -> Fabric UI sliders
typedef struct {
    float2 width;   // xypad, 0.0, 1.0, 0.5, Width
    float2 origin;  // xypad, -1.0, 1.0, 0.0, Origin
} PostUniforms;

fragment half4 postFragment( VertexData                 in        [[stage_in]],
                             constant PostUniforms     &uniforms  [[buffer( FragmentBufferMaterialUniforms )]],
                             texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{
    // Normalized UVs in [0, 1]
    float2 point = in.texcoord;

    // Map to normalized device space [-1, 1]
    float2 normCoord = point * 2.0 - 1.0;

    // Preserve sign, work in first quadrant
    float2 s = sign(normCoord);
    normCoord = abs(normCoord);

    // Smooth warp based on width range and origin offset
    float2 sm = smoothstep(uniforms.width.x,
                           uniforms.width.y,
                           normCoord + uniforms.origin);

    normCoord = 0.5 * normCoord + 0.5 * sm * normCoord;

    // Restore quadrant
    normCoord *= s;

    // Back to [0, 1] UV space
    float2 uv = normCoord * 0.5 + 0.5;

    return SAMPLER_FNC(renderTex, uv);
}
