// description: Draws antialiased contour lines from a single-channel depth image

#include <metal_stdlib>
using namespace metal;

#define SAMPLER_PRECISION float4
#define SAMPLER_TYPE texture2d<float>

#include "../../lygia/sampler.msl"
#include "../../Shaders/FabricImageTextureTransform.metal"

typedef struct {
    float lineThickness;  // slider, 0.0, 2.0, 1.0, Line Thickness
    float lineInterval;   // slider, 0.0, 1.0, 0.5, Line Interval
    float4 lineColor;     // color, 0.9, 0.6, 0.2, 1.0, Line Color
    float4 backgroundColor; // color, 0.1, 0.1, 0.1, 1.0, Background Color
} PostUniforms;

static float depthContourCoverage(float depth, float lineThickness, float lineInterval)
{
    if (lineThickness <= 0.0f || lineInterval <= 0.0f) {
        return 0.0f;
    }

    // Contour density is reciprocal to interval, so a linear interval control
    // concentrates nearly all useful adjustment at the bottom of the slider.
    // Squaring expands that high-density range while retaining exact endpoints.
    const float perceptualInterval = lineInterval * lineInterval;
    const float safeInterval = max(perceptualInterval, 0.000001f);
    const float contourPosition = depth / safeInterval;
    const float distanceToContour = abs(fract(contourPosition + 0.5f) - 0.5f);
    const float contourFwidth = max(fwidth(contourPosition), 0.000001f);
    const float halfLineWidth = 0.5f * lineThickness * contourFwidth;

    // Thickness changes the width of the line without reducing its peak opacity.
    return 1.0f - smoothstep(
        halfLineWidth,
        halfLineWidth + contourFwidth,
        distanceToContour
    );
}

fragment half4 postFragment(
    VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    constant float4x4 *imageTransforms [[buffer(FragmentBufferCustom10)]],
    texture2d<float, access::sample> depthTexture [[texture(FragmentTextureCustom0)]]
)
{
    const float2 imageUV = fabricTextureCoordinate(imageTransforms[0], in.texcoord);
    const float depth = SAMPLER_FNC(depthTexture, imageUV).r;
    const float contourCoverage = depthContourCoverage(
        depth,
        uniforms.lineThickness,
        uniforms.lineInterval
    );
    const float validContourCoverage = isfinite(contourCoverage) ? contourCoverage : 0.0f;
    const float4 color = mix(uniforms.backgroundColor, uniforms.lineColor, validContourCoverage);

    return half4(color);
}
