//
//  Posterize.metal
//  Fabric
//
// description: Reduces each linear RGB channel to a fixed number of color levels
//

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"
#include "../../Shaders/FabricImageTextureTransform.metal"

typedef struct {
    float levels; // slider, 2, 256, 8, Levels Per Channel
} PostUniforms;

fragment half4 postFragment(
    VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    constant float4x4 *imageTransforms [[buffer(FragmentBufferCustom10)]],
    texture2d<half, access::sample> renderTex [[texture(FragmentTextureCustom0)]]
)
{
    const half4 color = SAMPLER_FNC(renderTex, fabricTextureCoordinate(imageTransforms[0], in.texcoord));
    const float numberOfSteps = round(clamp(uniforms.levels, 2.0, 256.0) - 1.0);
    const float3 posterizedRGB = round( float3(color.rgb) * numberOfSteps) / numberOfSteps;

    return half4(half3(posterizedRGB), color.a);
}
