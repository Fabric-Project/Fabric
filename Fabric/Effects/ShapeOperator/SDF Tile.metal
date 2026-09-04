//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Tiles a signed distance field in a grid

#include "../../lygia/sampler.msl"
#include "../../lygia/draw/fill.msl"
#include "../../lygia/draw/stroke.msl"
#include "../../lygia/space/sqTile.msl"
#include "../../lygia/sdf/opRepeat.msl"
#include "../../Shaders/FabricImageTextureTransform.metal"

typedef struct {
    float tile; // slider, 1.0, 20.0, 1.0, Tile Size

} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    constant float4x4 *imageTransforms [[buffer(FragmentBufferCustom10)]],
    texture2d<float, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{
    float4 color = float4(0.0);

    float2 uv = sqTile(in.texcoord, uniforms.tile).xy;
    float sdf = SAMPLER_FNC( renderTex, fabricTextureCoordinate(imageTransforms[0], uv)).r;

    return half4(sdf);
}
