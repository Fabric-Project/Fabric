//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//

#define SAMPLER_PRECISION float4
#define SAMPLER_TYPE texture2d<float>
#define GAUSSIANBLUR_2D
//#define GAUSSIANBLUR1D_FAST13_TYPE float4
//#define GAUSSIANBLUR_TYPE float4
//#define GAUSSIANBLUR1D_TYPE float4

#include "../../lygia/sampler.msl"
#include "../../lygia/filter/gaussianBlur.msl"

typedef struct {
    float amount; // slider, 0.0, 1.0, 0.0, Amount
//    float2 direction; // xypad, -20.0, 20.0, 0.0, Direction
} PostUniforms;

fragment float4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<float, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{ 

//    uint width = renderTex.get_width();
//    uint height = renderTex.get_height();
//    float2 reslution = float2(width, height);
    
    float4 color = gaussianBlur13( renderTex, in.texcoord,  uniforms.amount);

    return color;
}
