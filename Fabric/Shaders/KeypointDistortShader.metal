//
//  DisplacementMaterial.metal
//
//
//  Created by Anton Marini on 7/4/25.
//
using namespace metal;

#include <metal_stdlib>
#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../lygia/sampler.msl"



// Input Uniform Buffer Struct type for our 2 Keypoint Buffers
struct KeypointUV {
    float2 uv;   // in 0..1
};


typedef struct {
    float amount; // slider, 0.0, 1.0, 0.0, Amount
    float alpha; // slider, 0.0, 5.0, 3.0, Alpha
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
                            constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
                            texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]],
                            constant KeypointUV* origKP   [[ buffer( FragmentBufferCustom0 )]],
                            constant KeypointUV* newKP    [[ buffer( FragmentBufferCustom1 )]],
                            constant uint* count           [[ buffer( FragmentBufferCustom2 ) ]]
)
{
    float2 uv = in.texcoord;
    
    float2 num = float2(0.0);
    float den = 0.0;
    
    //float2 size = float2(renderTex.get_width(), renderTex.get_height());
    
    // inverse-distance weighting to orig keypoint positions (in UV)
    // delta is computed from (new - orig), so caller doesn’t need to.
    for (uint i = 0; i < count[0]; ++i)
    {
        float2 pi = origKP[i].uv;
        float2 qi = newKP[i].uv;
        
        float2 distance = uv - pi;                         // distance to original keypoint from current uv coord
        float2 delta = qi - pi;                         // UV offset
        
        //
        float radiusD = max(length(distance) , 1e-6) ;

        float w = 1.0 / pow(radiusD, uniforms.alpha); //
//        float w = radiusD * uniforms.alpha ; //pow(radius, uniforms.alpha); //

        num += w * delta;
        den += w;

//        num += w * delta;
//        den += w;

    }
    
    // Calculated Displacement
    float2 disp = num;//(den > 0.0) ? (num / den)  : float2(0.0);

    // Normalize
    disp /= float(count[0]);

    // clamp to the requested [-1, 1] UV-offset range
    disp = clamp(disp, float2(-1.0), float2( 1.0));
    
    float2 finalUV =  mix(uv, uv + disp, uniforms.amount);
    
    return half4(finalUV.x, finalUV.y, length(disp), 1.0);
    
    return SAMPLER_FNC( renderTex, finalUV );
}
