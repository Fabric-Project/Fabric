//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Applies barrel lens distortion

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#define BARREL_TYPE half3
#define PINCUSHION_TYPE half3
#define BARREL_OCT_3

#include "../../lygia/sampler.msl"
#include "../../lygia/distort/barrel.msl"
#include "../../lygia/distort/pincushion.msl"
#include "../../Shaders/FabricImageTextureTransform.metal"


typedef struct {
    float pincushion; // slider, -0.6, 0.6, 0.0
    float barrel; // slider, 0.0, 0.2, 0.0
} PostUniforms;

static half3 fabricBarrel(
    texture2d<half, access::sample> texture,
    float4x4 textureTransform,
    float2 coordinate,
    float distance
) {
    half3 accumulatedColor = half3(0.0h);
    for (int octave = 0; octave < 12; ++octave) {
        const float amount = float(octave) * 0.2;
        const float2 sampleCoordinate = barrel(coordinate, amount, distance);
        accumulatedColor += SAMPLER_FNC(
            texture,
            fabricTextureCoordinate(textureTransform, sampleCoordinate)
        ).rgb;
    }
    return accumulatedColor / 12.0h;
}

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    constant float4x4 *imageTransforms [[buffer(FragmentBufferCustom10)]],
    texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{

	float2 uv = in.texcoord;

 	 uv = pincushion(uv, float2(1.0), uniforms.pincushion + 0.001);
//	half3 cushion = pincushion(renderTex, uv, float2(0.5), uniforms.amount);

	half3 cushion = fabricBarrel(renderTex, imageTransforms[0], uv, uniforms.barrel);

    return half4(cushion, 1.0); 
}
