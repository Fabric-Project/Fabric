//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Converts depth buffer values to linear depth

#define SAMPLER_PRECISION float4
#define SAMPLER_TYPE texture2d<float>

#include "../../lygia/sampler.msl"
#include "../../lygia/sample/clamp2edge.msl"
#include "../../lygia/space/linearizeDepth.msl"
#include "../../Shaders/FabricImageTextureTransform.metal"

typedef struct {
    float near; // input, Near
    float far; // input, Far
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    constant float4x4 *imageTransforms [[buffer(FragmentBufferCustom10)]],
    texture2d<float, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{
    const float2 imageUV = fabricTextureCoordinate(imageTransforms[0], in.texcoord);
    float color = linearizeDepth(sampleClamp2edge(renderTex, imageUV).r, uniforms.near, uniforms.far);
    return half4( half3(color), 1.0);
}
