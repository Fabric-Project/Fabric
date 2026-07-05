//
//  Hexagonal Pixelate.metal
//  Fabric
//
// description: Reduces resolution into hexagonal pixel cells
//

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"
#include "../../lygia/math/mod.msl"

typedef struct {
    float amount; // slider, 0.00000001, 1.0, 0.05, Amount
} PostUniforms;

fragment half4 postFragment(
    VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    texture2d<half, access::sample> renderTex [[texture(FragmentTextureCustom0)]]
)
{
    const float width = float(renderTex.get_width());
    const float height = float(renderTex.get_height());
    const float aspect = width / height;
    const float amount = max(uniforms.amount, 0.00000001);
    const float tilings = 1.0 / amount;

    const float2 gridRepeat = float2(1.0, 1.7320508);
    const float2 halfGridRepeat = 0.5 * gridRepeat;

    const float2 centeredUV = (in.texcoord - 0.5) * float2(aspect, 1.0);
    const float2 gridPosition = centeredUV * tilings;

    const float2 firstCellOffset =
        mod(gridPosition, gridRepeat) - halfGridRepeat;
    const float2 secondCellOffset =
        mod(gridPosition - halfGridRepeat, gridRepeat) - halfGridRepeat;

    const float2 nearestCellOffset =
        dot(firstCellOffset, firstCellOffset) < dot(secondCellOffset, secondCellOffset)
        ? firstCellOffset
        : secondCellOffset;

    const float2 cellCenter = gridPosition - nearestCellOffset;
    float2 sampleUV = cellCenter / tilings;
    sampleUV.x /= aspect;
    sampleUV = clamp(sampleUV + 0.5, 0.01, 0.99);

    return SAMPLER_FNC(renderTex, sampleUV);
}
