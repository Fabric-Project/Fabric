//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Converts HSV to RGB colour space

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"
#include "../../Shaders/FabricImageTextureTransform.metal"

typedef struct {
    
    float min; // slider, -1.0, 1.0, 0.0, Minimum
    float max; // slider, -1.0, 1.0, 1.0, Maximum
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    constant float4x4 *imageTransforms [[buffer(FragmentBufferCustom10)]],
    texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{
    half4 color = SAMPLER_FNC( renderTex, fabricTextureCoordinate(imageTransforms[0], in.texcoord));

    return clamp( color, uniforms.min, uniforms.max );
}
