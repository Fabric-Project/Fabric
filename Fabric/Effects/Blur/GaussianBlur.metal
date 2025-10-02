//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#define GAUSSIANBLUR_TYPE half4
#define GAUSSIANBLUR_2D

#include "../../lygia/sampler.msl"
#include "../../lygia/filter/gaussianBlur.msl"

typedef struct {
    float amount; // slider, 0.0, 50.0, 0.0, Amount
//    float2 direction; // xypad, -20.0, 20.0, 0.0, Direction
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{

    float2 resolution = float2(renderTex.get_width(), renderTex.get_height());
    float2 pixel = 1.0/resolution;
//    float2 st = (in.texcoord * resolution) * pixel;

    float ix = floor( uniforms.amount);
    float kernel_size = max(1.0, ix  );
    
    half4 color = gaussianBlur( renderTex, in.texcoord,  pixel, int(kernel_size));

    return half4(color);
}
