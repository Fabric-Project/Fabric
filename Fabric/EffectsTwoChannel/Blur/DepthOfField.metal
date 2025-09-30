//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//

#define SAMPLEDOF_TYPE half3
#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>
#define SAMPLEDOF_BLUR_SIZE 17
#define SAMPLEDOF_RAD_SCALE .9

#include "../../lygia/space/linearizeDepth.msl"



// #define SAMPLEDOF_DEBUG
#define SAMPLEDOF_COLOR_SAMPLE_FNC(TEX, UV) sampleClamp2edge(TEX, UV).rgb
#define SAMPLEDOF_DEPTH_SAMPLE_FNC(TEX, UV) linearizeDepth( sampleClamp2edge(TEX, UV).r, 0.01, 500.0)

#include "../../lygia/sample/clamp2edge.msl"
#include "../../lygia/sampler.msl"
#include "../../lygia/sample/dof.msl"

typedef struct {
    float focusPoint; // slider, 0.0, 0.2, 0.0, Focus
    float focusScale; // slider, 0.0, 0.05, 0.0, Scale
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]],
    texture2d<half, access::sample> renderTex2 [[texture( FragmentTextureCustom1 )]])
{
    half3 color = sampleDoF( renderTex, renderTex2,  in.texcoord, uniforms.focusScale, uniforms.focusPoint);

    return half4(color, 1.0);
}
