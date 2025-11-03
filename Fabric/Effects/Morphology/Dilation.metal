//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"

typedef struct {
    int radius; // slider, 0, DILATION_MAX_RADIUS, 2, Radius
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{
    const float2 pixelScale = float2(1.0 / float(renderTex.get_width()), 1.0 / float(renderTex.get_height()) );

    return dilation( renderTex, in.texcoord, pixelScale, uniforms.radius );
}
