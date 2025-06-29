//
//  BasicColorTexture.metal
//  Fabric
//
//  Created by Anton Marini on 6/29/25.
//

#include <metal_stdlib>

using namespace metal;


typedef struct {
} PostUniforms;

fragment float4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<float, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{
    constexpr sampler s = sampler( min_filter::linear, mag_filter::linear );

    const float aspect = float(renderTex.get_width()) / float(renderTex.get_height());
    
    float2 uv = in.texcoord;
//    uv.x *= aspect;
       

    return renderTex.sample( s, uv );
}
