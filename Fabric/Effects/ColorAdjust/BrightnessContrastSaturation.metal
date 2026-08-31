//
//  BasicColorTexture.metal
//  Fabric
//
//  Created by Anton Marini on 6/29/25.
//
// description: Adjusts brightness, contrast, and saturation

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"
#include "../../lygia/color/brightnessContrast.msl"
#include "../../lygia/color/luminance.msl"
#include "../../Shaders/FabricImageTextureTransform.metal"


typedef struct {
    float brightness; // slider, -1.0, 2.0, 0.0, Brightness
    float contrast; // slider, 0.0, 2.0, 1.0, Contrast
    float saturation; // slider, 0.0, 5.0, 1.0, Saturation
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    constant float4x4 *imageTransforms [[buffer(FragmentBufferCustom10)]],
    texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{
    half4 color = SAMPLER_FNC( renderTex, fabricTextureCoordinate(imageTransforms[0], in.texcoord));

    half4 bc = brightnessContrast(color, uniforms.brightness, uniforms.contrast);
    
    half3 luma = luminance(bc.rgb);

    half3 sat =  mix(luma , bc.rgb, uniforms.saturation);

    return half4(sat, bc.a);
}
