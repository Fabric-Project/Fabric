//
//  BasicColorTexture.metal
//  Fabric
//
//  Created by Anton Marini on 6/29/25.
//


#include "../../lygia/generative/wavelet.msl"


typedef struct {
    float timeR; // input, 0.0, Time Red
    float timeG; // input, 0.0, Time Green
    float timeB; // input, 0.0, Time Blue
    int octaves; // input, 2.0, Octaves
    float scaleR; // input, 2.0, Scale Red
    float scaleG; // input, 2.0, Scale Green
    float scaleB; // input, 2.0, Scale Blue
//    float smoothness; // slider, 0.0, 5.0, 1.0, Smoothness
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
                            constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]])
{
    half4 color = half4(half3(0.0), 1.0);
    
    half3 result = half3(1.0);
    for ( int i = 0; i < uniforms.octaves; i++)
    {
        result.r = wavelet(float3(result.r * uniforms.scaleR * in.texcoord, uniforms.timeR)) * 0.5 + 0.5;
        result.g = wavelet(float3(result.g * uniforms.scaleG * in.texcoord, uniforms.timeG)) * 0.5 + 0.5;
        result.b = wavelet(float3(result.b * uniforms.scaleB * in.texcoord, uniforms.timeB)) * 0.5 + 0.5;
    }
        
    color.rgb += result;
    return color;
}
