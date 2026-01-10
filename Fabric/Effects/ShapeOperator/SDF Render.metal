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
    float4 fillColor; // color,  Fill Color
    float fill; // slider, -1.0, 1.0, 0.0, Fill
    float4 borderColor; // color, Border Color
    float borderWidth; // slider, 0.0, 1.0, 0.0, Border Width
    float borderSize; // slider, -1.0, 1.0, 0.0, Border Offset
    float4 backgroundColor; // color,  Background Color
    float onion; // slider, 0.0, 1.0, 0.5, Onion

} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<float, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{
    float4 color = float4(0.0);

    float sdf = SAMPLER_FNC( renderTex, in.texcoord ).r;
  //  sdf = opOnion(sdf, uniforms.onion);

    float sdfStroke = stroke(sdf, uniforms.borderSize, uniforms.borderWidth);
//    sdfStroke = opOnion(sdfStroke, uniforms.onion);

    color += mix( uniforms.backgroundColor, uniforms.fillColor,  fill(sdf, uniforms.fill) );
    color = mix( color, uniforms.borderColor, sdfStroke);

    return half4(color);
}
