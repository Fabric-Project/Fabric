//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Detects edges using the Sobel operator

#define EDGESOBEL_TYPE half
#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"
#include "../../lygia/filter/edge/sobel.msl"
#include "../../Shaders/FabricImageTextureTransform.metal"


typedef struct {
//    float2 offset; // xypad, -10.0, 10.0, 1.0, Offset
    float2 offset; // input, 1.0, Offset
} PostUniforms;

static half fabricSobelSample(
    texture2d<half, access::sample> texture,
    float4x4 textureTransform,
    float2 coordinate
) {
    return sampleClamp2edge(
        texture,
        fabricTextureCoordinate(textureTransform, coordinate)
    ).r;
}

static half fabricSobel(
    texture2d<half, access::sample> texture,
    float4x4 textureTransform,
    float2 coordinate,
    float2 offset
) {
    const half topLeft = fabricSobelSample(texture, textureTransform, coordinate + float2(-offset.x, offset.y));
    const half left = fabricSobelSample(texture, textureTransform, coordinate + float2(-offset.x, 0.0));
    const half bottomLeft = fabricSobelSample(texture, textureTransform, coordinate + float2(-offset.x, -offset.y));
    const half top = fabricSobelSample(texture, textureTransform, coordinate + float2(0.0, offset.y));
    const half bottom = fabricSobelSample(texture, textureTransform, coordinate + float2(0.0, -offset.y));
    const half topRight = fabricSobelSample(texture, textureTransform, coordinate + offset);
    const half right = fabricSobelSample(texture, textureTransform, coordinate + float2(offset.x, 0.0));
    const half bottomRight = fabricSobelSample(texture, textureTransform, coordinate + float2(offset.x, -offset.y));
    const half horizontal = topLeft + 2.0h * left + bottomLeft - topRight - 2.0h * right - bottomRight;
    const half vertical = -topLeft - 2.0h * top - topRight + bottomLeft + 2.0h * bottom + bottomRight;
    return sqrt(horizontal * horizontal + vertical * vertical);
}


fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    constant float4x4 *imageTransforms [[buffer(FragmentBufferCustom10)]],
    texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{
    const float2 presentationSize = fabricPresentationSize(
        imageTransforms[0],
        float2(renderTex.get_width(), renderTex.get_height())
    );

    return fabricSobel(
        renderTex,
        imageTransforms[0],
        in.texcoord,
        uniforms.offset / presentationSize
    );
}
