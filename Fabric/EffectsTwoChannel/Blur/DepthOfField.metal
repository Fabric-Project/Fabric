//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Applies depth-of-field blur using a depth map

// #define SAMPLEDOF_DEBUG
#define SAMPLEDOF_TYPE half3
#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>
// 6
#define SAMPLEDOF_BLUR_SIZE 12

// .5
#define SAMPLEDOF_RAD_SCALE 2

#include "../../lygia/sample/clamp2edge.msl"
#include "../../lygia/sampler.msl"
#include "../../lygia/sample/dof.msl"
#include "../../Shaders/FabricImageTextureTransform.metal"

typedef struct {
    float focusPoint; // slider, 0.0, 1.0, 0.0, Focus
    float focusScale; // slider, 0.0, 1.0, 0.0, Scale
} PostUniforms;

static half3 fabricSampleDepthOfField(
    texture2d<half, access::sample> colorTexture,
    float4x4 colorTextureTransform,
    texture2d<half, access::sample> depthTexture,
    float4x4 depthTextureTransform,
    float2 coordinate,
    float focusPoint,
    float focusScale
) {
    const float2 colorPresentationSize = fabricPresentationSize(
        colorTextureTransform,
        float2(colorTexture.get_width(), colorTexture.get_height())
    );
    const float2 pixelScale = 1.0 / colorPresentationSize;
    const float centerDepth = float(SAMPLER_FNC(
        depthTexture,
        fabricTextureCoordinate(depthTextureTransform, coordinate)
    ).r);
    const float centerSize = getBlurSize(centerDepth, focusPoint, focusScale);
    half3 color = SAMPLER_FNC(
        colorTexture,
        fabricTextureCoordinate(colorTextureTransform, coordinate)
    ).rgb;

    float total = 1.0;
    float radius = SAMPLEDOF_RAD_SCALE;
    for (float angle = 0.0; radius < SAMPLEDOF_BLUR_SIZE; angle += GOLDEN_ANGLE) {
        const float2 sampleCoordinate = coordinate
            + float2(cos(angle), sin(angle)) * pixelScale * radius;
        const float sampleDepth = float(SAMPLER_FNC(
            depthTexture,
            fabricTextureCoordinate(depthTextureTransform, sampleCoordinate)
        ).r);
        float sampleSize = getBlurSize(sampleDepth, focusPoint, focusScale);
        if (sampleDepth > centerDepth) {
            sampleSize = clamp(sampleSize, 0.0, centerSize * 2.0);
        }
        const float percentage = smoothstep(radius - 0.5, radius + 0.5, sampleSize);
        const half3 sampleColor = SAMPLER_FNC(
            colorTexture,
            fabricTextureCoordinate(colorTextureTransform, sampleCoordinate)
        ).rgb;
        color += mix(color / half(total), sampleColor, half(percentage));
        total += 1.0;
        radius += SAMPLEDOF_RAD_SCALE / radius;
    }

    return color / half(total);
}

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    constant float4x4 *imageTransforms [[buffer(FragmentBufferCustom10)]],
    texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]],
    texture2d<half, access::sample> renderTex2 [[texture( FragmentTextureCustom1 )]])
{
    half3 color = fabricSampleDepthOfField(
        renderTex,
        imageTransforms[0],
        renderTex2,
        imageTransforms[1],
        in.texcoord,
        uniforms.focusPoint,
        uniforms.focusScale
    );

    return half4(color, 1.0);
}
