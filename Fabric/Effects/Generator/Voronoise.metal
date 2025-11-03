//
//  BasicColorTexture.metal
//  Fabric
//
//  Created by Anton Marini on 6/29/25.
//


#include "../../lygia/generative/voronoise.msl"


typedef struct {
    float time; // input, 0.0, Time
    float scale; // input, 2.0, Scale
    float smoothness; // slider, 0.0, 5.0, 1.0, Smoothness
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
                            constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]])
{
    half4 color = half4(half3(0.0), 1.0);
    half p = 0.5 - 0.5 * cos( uniforms.time );
    
    //p = p*p*(3.0-2.0*p);
    //p = p*p*(3.0-2.0*p);
    //p = p*p*(3.0-2.0*p);
    
    color.rgb += voronoise( float3(uniforms.scale *  in.texcoord, uniforms.time), p, uniforms.smoothness );
    
    return color;
}
