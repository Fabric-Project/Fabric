#include <metal_stdlib>
using namespace metal;

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"


// Uniforms -> Fabric UI
typedef struct {
    float amt;   // slider, 0.0, 2.0, 0.0, Amount
} PostUniforms;

fragment half4 postFragment( VertexData                        in        [[stage_in]],
                             constant PostUniforms            &u         [[buffer( FragmentBufferMaterialUniforms )]],
                             texture2d<half, access::sample>   tex0      [[texture( FragmentTextureCustom0 )]],
                             texture2d<half, access::sample>   tex1      [[texture( FragmentTextureCustom1 )]] )
{
    float2 uv = in.texcoord;

    // Sample lookup / displacement texture
    half4 look = SAMPLER_FNC(tex1, uv);

    // offs = vec2(look.y - look.x, look.w - look.z) * amt;
    float2 offs = float2(float(look.g - look.r),
                         float(look.a - look.b)) * u.amt;

    // Offset coordinates
    float2 coord = uv + offs;

    // Sample source texture at displaced coords
    return SAMPLER_FNC(tex0, coord);
}
