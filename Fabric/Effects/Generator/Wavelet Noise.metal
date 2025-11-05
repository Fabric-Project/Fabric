//
//  BasicColorTexture.metal
//  Fabric
//
//  Created by Anton Marini on 6/29/25.
//


#include "../../lygia/generative/wavelet.msl"


typedef struct {
    float time; // input, 0.0, Time
    int octaves; // input, 2.0, Octaves
    float scale; // input, 2.0, Scale
//    float smoothness; // slider, 0.0, 5.0, 1.0, Smoothness
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
                            constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]])
{
    half4 color = half4(half3(0.0), 1.0);
    
    
    half result = 1.0;
    for ( int i = 0; i < uniforms.octaves; i++)
    {
        result = wavelet(float3(result * uniforms.scale * in.texcoord, uniforms.time)) * 0.5 + 0.5;
    }
        
    color.rgb += result;
    return color;
}
