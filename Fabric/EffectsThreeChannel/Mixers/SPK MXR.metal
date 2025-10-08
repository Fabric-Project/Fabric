//
//  SPK MXR.metal
//  
//
//  Created by Toby Harris on 08/10/2025.
//

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"
#include "../../lygia/color/space/linear2gamma.msl"
#include "../../lygia/color/space/gamma2linear.msl"
#include "../../lygia/color/luminance.msl"

/*
SPARK-MIXER-v8
Combine two channels of video with both a crossfader and a 'maskfader' in a way that pleases me.
Toby Harris aka *spark
Sep2007  www.sparkav.co.uk (Quartz Composer / Image Kernel)
Feb2022  www.sparklive.co.uk (Unity Shaderlab)
Oct2025  www.sparklive.co.uk (Fabric / Metal Shader)
*/

typedef struct {
    float crossFade; // slider, 0.0, 1.0, 0.0, Cross Fade
    float maskFade; // slider, 0.0, 1.0, 0.5, Mask Fade
} PostUniforms;

half SPKFadeCurve(half fade)
{
    if (fade < 0.5h) return fade*2.0h;
    return 1.0h;
}

half SPKMaskCurve(half fade) {
    return (fade - 0.25h) * 2.0h;
}

half3 SPKMix(half3 aVec, half3 bVec, half3 maskVec, half crossFade, half maskFade)
{
    half luma = luminance(maskVec);

    // The mask image is used to key between the two main inputs
    // Control over this keying is via the maskfader, which will apply increasing contrast
    //    towards the extremes (e.g. 0 and 1), a flat white in the center (0.5)
    //    and invert the mask image past the center
    half maskFadeUpCurve = SPKMaskCurve(maskFade);
    half maskFadeDownCurve = SPKMaskCurve(1.0h - maskFade);
    half maskA = saturate(mix(maskFadeUpCurve, maskFadeDownCurve, luma));
    half maskB = saturate(mix(maskFadeDownCurve, maskFadeUpCurve, luma));

    half crossA = SPKFadeCurve(1.0h - crossFade);
    half crossB = SPKFadeCurve(crossFade);

    // To mix –
    // fade to black each channel according to crossfader
    //  ie. multiply A and B by the crossfader
    // and blend together with the masking lookup applied
    //  ie. multiply by mask amount
    //  ie. add together and divide by the amount of video channel being used
    half blendAmount = min(crossA + crossB, maskA + maskB);
    return (aVec*crossA*maskA + bVec*crossB*maskB)/blendAmount;
}

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<half, access::sample> tex0 [[texture( FragmentTextureCustom0 )]],
    texture2d<half, access::sample> tex1 [[texture( FragmentTextureCustom1 )]],
    texture2d<half, access::sample> tex2 [[texture( FragmentTextureCustom2 )]])
{
    half4 inAColor = linear2gamma(SAMPLER_FNC( tex0, in.texcoord ));
    half4 inBColor = linear2gamma(SAMPLER_FNC( tex1, in.texcoord ));
    half4 maskColor = linear2gamma(SAMPLER_FNC( tex2, in.texcoord ));
    
    half4 result;
    result.rgb = gamma2linear(
        SPKMix(inAColor.rgb, inBColor.rgb, maskColor.rgb, uniforms.crossFade, uniforms.maskFade)
    );
    result.a = 1.0h;
    
    return result;
}
