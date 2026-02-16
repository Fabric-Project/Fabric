//
//  BasicColorTexture.metal
//  Fabric
//
//  Created by Anton Marini on 6/29/25.
//


#include "../../lygia/generative/fbm.msl"


typedef struct {
    float4 color1; // color, Start Color
    float4 color2; // color, End Color
//    float smoothness; // slider, 0.0, 5.0, 1.0, Smoothness
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
                            constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]])
{
    half4 color = half4( mix(uniforms.color1, uniforms.color2, in.texcoord.x) );
    
    return color;
}
