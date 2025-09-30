//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//

#define SAMPLER_PRECISION float4
#define SAMPLER_TYPE texture2d<float>

#include "../../lygia/sampler.msl"
#include "../../lygia/sample/clamp2edge.msl"
#include "../../lygia/space/linearizeDepth.msl"

typedef struct {
    float near; // input, Near
    float far; // input, Far
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<float, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{
    float color = linearizeDepth( sampleClamp2edge(renderTex, in.texcoord).r, uniforms.near, uniforms.far);
    return half4( half3(color), 1.0);
}
