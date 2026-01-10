//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//

#include "../../lygia/sampler.msl"
#include "../../lygia/draw/fill.msl"
#include "../../lygia/draw/stroke.msl"
#include "../../lygia/space/sqTile.msl"

typedef struct {
    float tile; // slider, 1.0, 20.0, 1.0, Tile Size

} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<float, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{
    float4 color = float4(0.0);

    float2 uv = sqTile(in.texcoord, uniforms.tile).xy;
    float sdf = SAMPLER_FNC( renderTex, uv ).r;

    return float4(sdf);
}
