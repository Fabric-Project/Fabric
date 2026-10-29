#ifndef FABRIC_IMAGE_TEXTURE_TRANSFORM_METAL
#define FABRIC_IMAGE_TEXTURE_TRANSFORM_METAL

#include <metal_stdlib>
using namespace metal;

inline float2 fabricTextureCoordinate(float4x4 textureTransform, float2 coordinate)
{
    return (textureTransform * float4(coordinate, 0.0, 1.0)).xy;
}

inline float2 fabricPresentationSize(float4x4 textureTransform, float2 textureSize)
{
    return abs((textureTransform * float4(textureSize, 0.0, 0.0)).xy);
}

#endif
