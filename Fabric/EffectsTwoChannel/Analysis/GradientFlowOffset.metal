// description: Displaces a source image along a signed-RG optical flow / velocity field.
//
// Industry-standard flow coordinate system (matches LucasKanadeOpticalFlowNode and
// Satin's velocity buffer):
//   tex1.r = X displacement in UV space, positive = rightward
//   tex1.g = Y displacement in UV space, positive = downward (texture-space convention)
//
// This is a FORWARD warp: positive flow moves the sample coordinate in the flow direction,
// so the image appears to scroll opposite to the flow (i.e. motion along +X shifts pixels left).
// For motion compensation / inverse warp, negate amt.

#include <metal_stdlib>
using namespace metal;

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"

typedef struct {
    float amt;   // slider, -2.0, 2.0, 1.0, Amount
} PostUniforms;

fragment half4 postFragment( VertexData                        in        [[stage_in]],
                             constant PostUniforms            &u         [[buffer( FragmentBufferMaterialUniforms )]],
                             texture2d<half, access::sample>   tex0      [[texture( FragmentTextureCustom0 )]],
                             texture2d<half, access::sample>   tex1      [[texture( FragmentTextureCustom1 )]] )
{
    float2 uv = in.texcoord;

    // Sample the flow / velocity field.
    // Expects standard signed-RG format: R = dx (rightward +), G = dy (downward +).
    // Compatible with: LucasKanadeOpticalFlowNode, Satin velocity buffers.
    half2 flow = SAMPLER_FNC(tex1, uv).rg;

    // Displace the UV coordinate along the flow direction.
    float2 coord = mix(uv, uv + float2(flow), u.amt);

    return SAMPLER_FNC(tex0, coord);
}
