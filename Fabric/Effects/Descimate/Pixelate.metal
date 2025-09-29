//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"

// From Satin, not Lygia FWIW
#include "Library/Repeat.metal"


typedef struct {
    float amount; // slider, 0.00000001, 1.0, 0.00000001, Amount
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{

    const float aspect = float(renderTex.get_width()) / float(renderTex.get_height());
    
    float2 uv = in.texcoord;
    uv.x *= aspect;
    
    float div = 1.0 * uniforms.amount;
    int2 cell = repeat( uv, div );
    
    float2 suv = float2(cell) * div;
    suv.x /= aspect;

    return SAMPLER_FNC( renderTex, suv );
}
