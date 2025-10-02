//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//

// #define SAMPLEDOF_DEBUG
#define SAMPLEDOF_TYPE half3
#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>
// 6
#define SAMPLEDOF_BLUR_SIZE 12

// .5
#define SAMPLEDOF_RAD_SCALE 2

#include "../../lygia/sample/clamp2edge.msl"
#include "../../lygia/sampler.msl"
#include "../../lygia/sample/dof.msl"

typedef struct {
    float focusPoint; // slider, 0.0, 1.0, 0.0, Focus
    float focusScale; // slider, 0.0, 1.0, 0.0, Scale
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]],
    texture2d<half, access::sample> renderTex2 [[texture( FragmentTextureCustom1 )]])
{
    half3 color = sampleDoF( renderTex, renderTex2, in.texcoord, uniforms.focusPoint, uniforms.focusScale);

    return half4(color, 1.0);
}
