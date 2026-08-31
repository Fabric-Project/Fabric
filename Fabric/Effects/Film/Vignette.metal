//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Darkens the image edges with a vignette

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>
#define GRAIN_TYPE half3

#include "../../lygia/sampler.msl"
#include "../../lygia/distort/grain.msl"
#include "../../Shaders/FabricImageTextureTransform.metal"

typedef struct {
    float radius; // slider, 0.0, 1.0, 0.5, Radius
    float smoothness; // slider, 0.01, 1.0, 0.1, Smoothness
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    constant float4x4 *imageTransforms [[buffer(FragmentBufferCustom10)]],
    texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{
    constexpr sampler s = sampler( min_filter::linear, mag_filter::linear );

    float v = uniforms.radius - distance(in.texcoord, float2(0.5));
    v = smoothstep(-uniforms.smoothness, uniforms.smoothness, v);
    
    const float2 imageUV = fabricTextureCoordinate(imageTransforms[0], in.texcoord);
    half4 color = renderTex.sample(s, imageUV);

    return color * v;
}
