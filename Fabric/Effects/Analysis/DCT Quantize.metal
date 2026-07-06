//
//  DCT Quantize.metal
//  Fabric
//
// description: Quantizes block DCT coefficients with frequency-dependent loss
//

#include <metal_stdlib>
using namespace metal;

typedef struct {
    int blockSize;              // slider, 2, 32, 8, Block Size
    float quantization;         // slider, 0.0, 1.0, 0.02, Quantization
    float highFrequencyLoss;    // slider, 0.0, 16.0, 4.0, High Frequency Loss
    float falloff;              // slider, 0.1, 4.0, 1.5, Frequency Falloff
    float frequencyCutoff;      // slider, 0.0, 1.0, 1.0, Frequency Cutoff
    float dcQuantization;       // slider, 0.0, 4.0, 0.25, DC Quantization
    float coefficientDropout;   // slider, 0.0, 1.0, 0.0, Coefficient Dropout
    float3 channelStrength;     // slider, 0.0, 4.0, 1.0, Channel Strength
} PostUniforms;

static float dctCoefficientRandom(uint2 blockCoordinate, uint2 frequencyCoordinate)
{
    float2 seed = float2(
        blockCoordinate.x * 131u + frequencyCoordinate.x * 17u,
        blockCoordinate.y * 197u + frequencyCoordinate.y * 29u
    );
    return fract(sin(dot(seed, float2(12.9898, 78.233))) * 43758.5453);
}

fragment half4 postFragment(
    VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    texture2d<half, access::read> coefficientTexture [[texture(FragmentTextureCustom0)]]
)
{
    const uint2 textureSize = uint2(
        coefficientTexture.get_width(),
        coefficientTexture.get_height()
    );
    const uint2 coordinate = min(
        uint2(in.texcoord * float2(textureSize)),
        textureSize - 1
    );
    const half4 source = coefficientTexture.read(coordinate);

    const uint blockSize = uint(clamp(uniforms.blockSize, 2, 32));
    const uint2 frequencyCoordinate = coordinate % blockSize;
    const uint2 blockCoordinate = coordinate / blockSize;
    const uint2 blockOrigin = blockCoordinate * blockSize;
    const uint2 blockExtent = min(uint2(blockSize), textureSize - blockOrigin);
    const bool isDC = all(frequencyCoordinate == uint2(0));

    const float2 frequencyDenominator = max(float2(blockExtent) - 1.0, 1.0);
    const float2 normalizedFrequencyCoordinate =
        float2(frequencyCoordinate) / frequencyDenominator;
    const float normalizedFrequency =
        0.5 * (normalizedFrequencyCoordinate.x + normalizedFrequencyCoordinate.y);
    const float frequencyCutoff = clamp(uniforms.frequencyCutoff, 0.0, 1.0);
    const float coefficientDropout = clamp(uniforms.coefficientDropout, 0.0, 1.0);

    float3 coefficients = float3(source.rgb);

    if (!isDC && normalizedFrequency > frequencyCutoff) {
        coefficients = 0.0;
    }
    else if (!isDC
             && dctCoefficientRandom(blockCoordinate, frequencyCoordinate)
                < coefficientDropout) {
        coefficients = 0.0;
    }
    else if (uniforms.quantization > 0.0) {
        const float frequencyWeight = isDC
            ? max(uniforms.dcQuantization, 0.0)
            : 1.0 + max(uniforms.highFrequencyLoss, 0.0)
                * pow(normalizedFrequency, max(uniforms.falloff, 0.0001));
        const float3 quantizationStep =
            uniforms.quantization
            * frequencyWeight
            * max(uniforms.channelStrength, float3(0.0));
        const bool3 shouldQuantize = quantizationStep > float3(0.000001);
        const float3 safeQuantizationStep = max(
            quantizationStep,
            float3(0.000001)
        );
        const float3 quantizedCoefficients =
            round(coefficients / safeQuantizationStep) * safeQuantizationStep;

        coefficients = select(
            coefficients,
            quantizedCoefficients,
            shouldQuantize
        );
    }

    return half4(half3(coefficients), source.a);
}
