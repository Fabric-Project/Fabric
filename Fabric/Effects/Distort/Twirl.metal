#include <metal_stdlib>
using namespace metal;

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"


// Uniforms -> Fabric UI sliders
typedef struct {
    float  twirl;   // slider, -50.0, 50.0, 0.0, Twirl
    float  size;    // slider, 0.0, 5.0, 0.5, Size
    float2 origin;  // xypad, -1.0, 1.0, 0.0, Origin
} PostUniforms;

fragment half4 postFragment( VertexData                        in        [[stage_in]],
                             constant PostUniforms            &uniforms  [[buffer( FragmentBufferMaterialUniforms )]],
                             texture2d<half, access::sample>   renderTex [[texture( FragmentTextureCustom0 )]] )
{
    // Normalized coordinates [0, 1]
    float2 point = in.texcoord;

    // Map to [-1, 1]
    float2 normCoord = point * 2.0f - 1.0f;

    // Twirl origin in normalized space
    normCoord += uniforms.origin;

    // Polar coordinates
    float r   = length(normCoord);
    float phi = atan2(normCoord.y, normCoord.x);

    // Twirl falloff via smoothstep
    float falloff = 1.0f - smoothstep(-uniforms.size, uniforms.size, r);
    phi += falloff * uniforms.twirl;

    // Back to Cartesian
    normCoord = float2(r * cos(phi), r * sin(phi));

    // Remove origin offset
    normCoord -= uniforms.origin;

    // Back to [0, 1] UV space
    float2 uv = normCoord * 0.5f + 0.5f;
    uv = clamp(uv, 0.0f, 1.0f);

    // Sample with Lygia sampler helper
    return SAMPLER_FNC(renderTex, uv);
}
