//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//

#include "../../lygia/sampler.msl"
#include "../../lygia/draw/fill.msl"
#include "../../lygia/draw/stroke.msl"
#include "../../lygia/sdf/opOnion.msl"

typedef struct {
    float onion; // slider, 0.0, 1.0, 0.0, Onion

} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<float, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{
    float2 coords = in.texcoord;
    float sdf = SAMPLER_FNC( renderTex, coords ).r;
    sdf = opOnion(sdf, uniforms.onion);

    return half4(sdf);
}
