//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
#include <metal_stdlib>
using namespace metal;

#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"

// Uniforms → Fabric UI slider
typedef struct {
    float amount;   // slider, 0.0, 2.0, 0.5, Amount
} PostUniforms;

fragment half4 postFragment( VertexData                        in        [[stage_in]],
                             constant PostUniforms            &uniforms  [[buffer( FragmentBufferMaterialUniforms )]],
                             texture2d<half, access::sample>   tex        [[texture( FragmentTextureCustom0 )]] )
{
    float2 uv = in.texcoord;

    half4 input0 = SAMPLER_FNC(tex, uv);

    // Filters
    const half4 redfilter        = half4(1.0h, 0.0h, 0.0h, 1.0h);
    const half4 greenfilter      = half4(0.0h, 1.0h, 0.0h, 1.0h);
    const half4 bluefilter       = half4(0.0h, 0.0h, 1.0h, 1.0h);

    const half4 redorangefilter  = half4(0.99h, 0.263h, 0.0h, 1.0h);

    const half4 cyanfilter       = half4(0.0h, 1.0h, 1.0h, 1.0h);
    const half4 magentafilter    = half4(1.0h, 0.0h, 1.0h, 1.0h);
    const half4 yellowfilter     = half4(1.0h, 1.0h, 0.0h, 1.0h);

    // Camera / dye layers:
    // greenrecord: straight green
    // bluerecord : magenta-filtered layer (blue+red)
    // redrecord  : warm red/orange-biased layer
    half4 greenrecord = input0 * greenfilter;
    half4 bluerecord  = input0 * magentafilter;
    half4 redrecord   = input0 * redorangefilter;

    // Convert each record to a monochrome "negative" (luma-ish)
    half redL   = (redrecord.r   + redrecord.g   + redrecord.b)   / 3.0h;
    half greenL = (greenrecord.r + greenrecord.g + greenrecord.b) / 3.0h;
    half blueL  = (bluerecord.r  + bluerecord.g  + bluerecord.b)  / 3.0h;

    half4 rednegative   = half4(redL);
    half4 greennegative = half4(greenL);
    half4 bluenegative  = half4(blueL);

    // Re-filter negatives through complementary dye layers
    half4 redoutput   = rednegative   + cyanfilter;
    half4 greenoutput = greennegative + magentafilter;
    half4 blueoutput  = bluenegative  + yellowfilter;

    // Multiply all three for final print
    half4 result = redoutput * greenoutput * blueoutput;

    // Blend with original
    return mix(input0, result, half(uniforms.amount));
}
