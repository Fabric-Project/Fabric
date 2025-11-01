//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//

// #define SAMPLEDOF_DEBUG
#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sample/clamp2edge.msl"
#include "../../lygia/sampler.msl"

typedef struct {
    float amount; // slider, 0.0, 1.0, 0.0, Displacement Amount
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]],
    texture2d<half, access::sample> renderTex2 [[texture( FragmentTextureCustom1 )]],
    texture2d<half, access::sample> renderTex3 [[texture( FragmentTextureCustom2 )]]
)
{
    half4 displacement = SAMPLER_FNC( renderTex2, in.texcoord );
    
    half mask = SAMPLER_FNC( renderTex3, in.texcoord ).r;

    float2 displaceAmount = float2(displacement.xy) * float2(uniforms.amount) * float2(mask);
    
    half4 color = SAMPLER_FNC( renderTex, mix(in.texcoord, float2(displacement.xy), displaceAmount) );

    return color;
}
