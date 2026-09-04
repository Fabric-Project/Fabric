#include <metal_stdlib>
#include "FabricImageTextureTransform.metal"

using namespace metal;

struct PostUniforms {
    float unused;
};

struct CropUniforms {
    float2 origin;
    float2 size;
    float4x4 textureTransform;
};

fragment half4 postFragment(
    VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    constant CropUniforms &crop [[buffer(FragmentBufferCustom0)]],
    texture2d<half, access::sample> sourceTexture [[texture(FragmentTextureCustom0)]])
{
    constexpr sampler sourceSampler(
        coord::normalized,
        address::clamp_to_edge,
        min_filter::linear,
        mag_filter::linear
    );
    const float2 presentationCoordinate = crop.origin + in.texcoord * crop.size;
    const float2 storedCoordinate = fabricTextureCoordinate(
        crop.textureTransform,
        presentationCoordinate
    );
    return sourceTexture.sample(sourceSampler, storedCoordinate);
}
