//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Expands bright regions (morphological dilation)

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"
#include "../../Shaders/FabricImageTextureTransform.metal"

typedef struct {
    int radius; // slider, 0, DILATION_MAX_RADIUS, 2, Radius
} PostUniforms;

static half fabricDilation(
    texture2d<half, access::sample> texture,
    float4x4 textureTransform,
    float2 coordinate,
    float2 pixelScale,
    int radius
) {
    const float inverseRadius = 1.0 / float(radius);
    half accumulatedValue = 0.0h;
    float accumulatedWeight = 0.0;

    for (int horizontal = -radius; horizontal <= radius; ++horizontal) {
        for (int vertical = -radius; vertical <= radius; ++vertical) {
            const float2 radiusOffset = float2(horizontal, vertical);
            const float2 kernelCoordinate = radiusOffset * inverseRadius * 2.0;
            const float2 sampleCoordinate = coordinate + radiusOffset * pixelScale;
            const float kernelWeight = saturate(1.0 - dot(kernelCoordinate, kernelCoordinate));
            const half sampleValue = SAMPLER_FNC(
                texture,
                fabricTextureCoordinate(textureTransform, sampleCoordinate)
            ).r;
            const half weightedValue = sampleValue + half(kernelWeight);
            if (weightedValue > accumulatedValue) {
                accumulatedValue = weightedValue;
                accumulatedWeight = kernelWeight;
            }
        }
    }

    return accumulatedValue - half(accumulatedWeight);
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
    const float2 pixelScale = 1.0 / presentationSize;

    return fabricDilation(renderTex, imageTransforms[0], in.texcoord, pixelScale, uniforms.radius);
}
