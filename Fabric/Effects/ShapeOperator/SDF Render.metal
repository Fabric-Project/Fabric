//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Renders a signed distance field to colour

#include "../../lygia/sampler.msl"
#include "../../lygia/draw/fill.msl"
#include "../../lygia/draw/stroke.msl"
#include "../../lygia/sdf/opOnion.msl"
#include "../../Shaders/FabricImageTextureTransform.metal"

typedef struct {
    float4 fillColor; // color,  Fill Color
    float fill; // slider, -1.0, 1.0, 0.0, Fill
    float4 borderColor; // color, Border Color
    float borderWidth; // slider, 0.0, 1.0, 0.0, Border Width
    float borderSize; // slider, -1.0, 1.0, 0.0, Border Offset
    float4 backgroundColor; // color,  Background Color

} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    constant float4x4 *imageTransforms [[buffer(FragmentBufferCustom10)]],
    texture2d<float, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{
    float4 color = float4(0.0);

    float sdf = SAMPLER_FNC( renderTex, fabricTextureCoordinate(imageTransforms[0], in.texcoord)).r;
//    sdf = opOnion(sdf, uniforms.onion);

    float sdfStroke = stroke(sdf, uniforms.borderSize, uniforms.borderWidth);
//    sdfStroke = opOnion(sdfStroke, uniforms.onion);

    color += mix( uniforms.backgroundColor, uniforms.fillColor,  fill(sdf, uniforms.fill) );
    color = mix( color, uniforms.borderColor, sdfStroke);

    return half4(color);
}
