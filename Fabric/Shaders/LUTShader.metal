//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../lygia/sampler.msl"

typedef struct {
    float amount; // slider, 0.0, 2.0, 1.0, Amount
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]],
    texture3d<half, access::sample> lutTex [[texture( FragmentTextureCustom1 )]]
    )
{
    constexpr sampler s = sampler( min_filter::linear, mag_filter::linear );

    half4 rgba = SAMPLER_FNC(renderTex, in.texcoord);

    // Sample the 3D LUT
    half4 lutColor = lutTex.sample(s, float3(rgba.rgb) );
    lutColor = half4(lutColor.rgb, rgba.a);

    return mix(rgba, lutColor, half4(uniforms.amount));
}
