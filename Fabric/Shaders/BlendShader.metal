//
//  Blend.metal
//  Fabric
//
//  Created by Claude on 4/11/26.
//
// description: Blend two images using a selectable blend mode

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../lygia/sampler.msl"
#include "../lygia/color/blend.msl"
#include "../lygia/color/composite/sourceOver.msl"

typedef struct {
    float mode;   // input, 0, Mode
    float amount; // slider, 0.0, 1.0, 0.0, Amount
} BlendUniforms;

half3 applyBlendMode(int mode, half3 a, half3 b)
{
    switch (mode)
    {
        case 0:  return blendAdd(a, b);
        case 1:  return blendAverage(a, b);
        case 2:  return blendColor(a, b);
        case 3:  return blendColorBurn(a, b);
        case 4:  return blendColorDodge(a, b);
        case 5:  return blendDarken(a, b);
        case 6:  return blendDifference(a, b);
        case 7:  return blendExclusion(a, b);
        case 8:  return blendGlow(a, b);
        case 9:  return blendHardLight(a, b);
        case 10: return blendHardMix(a, b);
        case 11: return blendHue(a, b);
        case 12: return blendLighten(a, b);
        case 13: return blendLinearBurn(a, b);
        case 14: return blendLinearDodge(a, b);
        case 15: return blendLinearLight(a, b);
        case 16: return blendLuminosity(a, b);
        case 17: return blendMultiply(a, b);
        case 18: return blendNegation(a, b);
        case 19: return blendOverlay(a, b);
        case 20: return blendPhoenix(a, b);
        case 21: return blendPinLight(a, b);
        case 22: return blendReflect(a, b);
        case 23: return blendSaturation(a, b);
        case 24: return blendScreen(a, b);
        case 25: return blendSoftLight(a, b);
        case 26: return blendSubtract(a, b);
        case 27: return blendVividLight(a, b);
        default: return blendAdd(a, b);
    }
}

fragment half4 postFragment( VertexData in [[stage_in]],
    constant BlendUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<half, access::sample> tex0 [[texture( FragmentTextureCustom0 )]],
    texture2d<half, access::sample> tex1 [[texture( FragmentTextureCustom1 )]] )
{
    int mode = int(uniforms.mode);
    half amount = half(uniforms.amount);
    half4 srcColor = SAMPLER_FNC( tex0, in.texcoord );
    half4 dstColor = SAMPLER_FNC( tex1, in.texcoord );

    half3 blend = applyBlendMode(mode, srcColor.rgb, dstColor.rgb);
    half a = compositeSourceOver(srcColor.a, dstColor.a);

    half4 result;
    result.rgb = mix(srcColor.rgb, blend, amount);
    result.a = mix(srcColor.a, a, amount);

    return result;
}
