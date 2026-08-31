//
//  Triangular Pixelate.metal
//  Fabric
//
// description: Reduces resolution into triangular pixel cells
//

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"
#include "../../Shaders/FabricImageTextureTransform.metal"

typedef struct {
    float amount; // slider, 0.00000001, 1.0, 0.03, Amount
} PostUniforms;

fragment half4 postFragment(
    VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    constant float4x4 *imageTransforms [[buffer(FragmentBufferCustom10)]],
    texture2d<half, access::sample> renderTex [[texture(FragmentTextureCustom0)]]
)
{
    const float2 presentationSize = fabricPresentationSize(
        imageTransforms[0],
        float2(renderTex.get_width(), renderTex.get_height())
    );
    const float amount = max(uniforms.amount, 0.00000001);
    const float2 pixelating = float2(1.0, presentationSize.x / presentationSize.y) * amount;

    float2 uv = (in.texcoord - 0.5) / pixelating;

    const float2x2 triangleSpaceTransform = float2x2(
        float2(1.0, 1.0),
        float2(0.6, -0.6)
    );
    float2 trianglePosition = fract(triangleSpaceTransform * uv);

    if (trianglePosition.x > trianglePosition.y) {
        trianglePosition.x -= 0.5;
    }

    const float2x2 sampleOffsetTransform = float2x2(
        float2(0.5, 0.833),
        float2(0.5, -0.833)
    );
    uv -= sampleOffsetTransform * trianglePosition + float2(-0.25, 0.25);

    const float2 sampleUV = clamp(uv * pixelating + 0.5, 0.01, 0.99);
    return SAMPLER_FNC(renderTex, fabricTextureCoordinate(imageTransforms[0], sampleUV));
}
