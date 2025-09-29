//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//

#define EDGESOBEL_TYPE half
#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"
#include "../../lygia/filter/edge/sobel.msl"


typedef struct {
    float2 offset; // xypad, -10.0, 10.0, 1.0, Offset
} PostUniforms;


fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{
    uint width = renderTex.get_width();
    uint height = renderTex.get_height();

    return edgeSobel(renderTex, in.texcoord, uniforms.offset / float2(width, height)) ;
}
