//
//  BasicColorTexture.metal
//  Fabric
//
//  Created by Anton Marini on 6/29/25.
//

//#define SAMPLER_PRECISION half4
//#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"
#include "../../lygia/color/brightnessContrast.msl"


typedef struct {
    float brightness; // slider, -1.0, 2.0, 0.0, Brightness
    float contrast; // slider, 0.0, 2.0, 1.0, Contrast
} PostUniforms;

fragment float4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<float, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{
    float4 color = SAMPLER_FNC( renderTex, in.texcoord );

    return brightnessContrast(color, uniforms.brightness, uniforms.contrast);
}
