//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//


#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#define BARREL_TYPE half3
#define PINCUSHION_TYPE half3
#define BARREL_OCT_3

#include "../../lygia/sampler.msl"
#include "../../lygia/distort/barrel.msl"
#include "../../lygia/distort/pincushion.msl"


typedef struct {
    float pincushion; // slider, -0.6, 0.6, 0.0
    float barrel; // slider, 0.0, 0.2, 0.0
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{

   	float2 inRatio = float2(renderTex.get_width(), renderTex.get_height());
   	float2 outRatio = float2(renderTex.get_height(), renderTex.get_width());

	float2 uv = in.texcoord;

 	 uv = pincushion(uv, float2(1.0), uniforms.pincushion + 0.001);
//	half3 cushion = pincushion(renderTex, uv, float2(0.5), uniforms.amount);

	half3 cushion = barrel(renderTex, uv, uniforms.barrel);

    return half4(cushion, 1.0); 
}
