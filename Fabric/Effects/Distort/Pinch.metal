#include <metal_stdlib>
using namespace metal;

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"

// Uniforms -> Fabric UI sliders
typedef struct {
    float  pinch;   // slider, 0.0, 2.0, 0.0, Pinch
    float2 origin;  // xypad, -1.0, 1.0, 0.0, Origin
} PostUniforms;

fragment half4 postFragment( VertexData                        in        [[stage_in]],
                             constant PostUniforms            &uniforms  [[buffer( FragmentBufferMaterialUniforms )]],
                             texture2d<half, access::sample>   renderTex [[texture( FragmentTextureCustom0 )]] )
{
    // Normalized coordinates [0, 1]
    float2 point = in.texcoord;

    // Map to [-1, 1]
    float2 normCoord = point * 2.0 - 1.0;

    // Apply origin offset in normalized space
    normCoord += uniforms.origin;

    // Polar coordinates
    float r   = length(normCoord);
    float phi = atan2(normCoord.y, normCoord.x);

    // r = pow(r, 1.0 / (1.0 - pinch * -1.0)) * 0.8;
    // -> r = pow(r, 1.0 / (1.0 + pinch)) * 0.8;
    float k = 1.0 + uniforms.pinch;
    k = max(k, 0.0001);              // avoid division by zero
    float exponent = 1.0 / k;
    r = pow(r, exponent) * 0.8;

    // Back to Cartesian
    normCoord = float2(r * cos(phi), r * sin(phi));

    // Remove origin offset
    normCoord -= uniforms.origin;

    // Back to [0, 1] UV space
    float2 uv = normCoord * 0.5 + 0.5;
    uv = clamp(uv, 0.0, 1.0);

    // Sample with Lygia sampler helper
    return SAMPLER_FNC(renderTex, uv);
}
