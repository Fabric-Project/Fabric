//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//


#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"
#include "../../lygia/space/kaleidoscope.msl"


typedef struct {
	float amount; // slider, 0.0, 1.0, 0.0, Amount
	float segmentCount; // slider, 0.0, 12.0, 0.0, Segment Count
	float phase; // slider, 0.0, 6.282, 0.0, Phase
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{

	float amount = uniforms.amount;//clamp(uniforms.segmentCount, 0.0, 1.0 );
 	float segmentCount = clamp(uniforms.segmentCount, 1.0, 12.0);

	float2 uv = kaleidoscope(in.texcoord, segmentCount, uniforms.phase);
	
	float2 coords = mix(in.texcoord, texcoord, float2(amount));
    
	half4 color = SAMPLER_FNC( renderTex, coords);

	return color;
}
