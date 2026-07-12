//
//  DCT Corruption.metal
//  Fabric
//
// description: Artistically corrupts block DCT coefficients with biased quantization and per-block instability
//

#include <metal_stdlib>
using namespace metal;

typedef struct {
    int blockSize;              // slider, 2, 32, 8, Block Size
    float strength;             // slider, 0.0, 1.0, 0.35, Strength
    float quantization;         // slider, 0.0, 4.0, 0.02, Coefficient Step
    float frequencyBias;        // slider, 0.0, 8.0, 3.0, Frequency Bias
    float blockInstability;     // slider, 0.0, 1.0, 0.15, Block Instability
    float blockWave;            // slider, 0.0, 1.0, 0.0, Block Wave
    float temporalDrift;        // slider, 0.0, 4.0, 0.0, Temporal Drift
    float coefficientBias;      // slider, -1.0, 1.0, 0.0, Coefficient Bias
    float biasReturn;           // slider, 0.0, 1.0, 1.0, Bias Return
    float dcLevelShift;         // slider, -0.125, 0.125, 0.0, DC Level Shift
    float dcLevelReturn;        // slider, 0.0, 1.0, 1.0, DC Level Return
    float dcLevelShiftChannel1; // slider, 0.0, 1.0, 1.0, DC Level Shift Channel 1
    float dcLevelShiftChannel2; // slider, 0.0, 1.0, 0.0, DC Level Shift Channel 2
    float dcLevelShiftChannel3; // slider, 0.0, 1.0, 0.0, DC Level Shift Channel 3
    float lowFrequencyProtect;  // slider, 0.0, 1.0, 0.75, Low Frequency Protect
    float3 channelStrength;     // slider, 0.0, 4.0, 1.0, Channel Strength
    float time;                 // input, 0.0, Time
} PostUniforms;

static float dctCorruptionRandom(float2 seed)
{
    return fract(sin(dot(seed, float2(12.9898, 78.233))) * 43758.5453);
}

static float dctCorruptionBlockVariation(
    uint2 blockCoordinate,
    float blockInstability,
    float blockWave,
    float temporalDrift,
    float time
) {
    const float2 blockSeed = float2(blockCoordinate);
    const float randomValue = dctCorruptionRandom(blockSeed + 17.0);
    const float staticVariation = mix(1.0, 0.5 + randomValue * 1.5, blockInstability);

    const float driftPhase = dot(blockSeed, float2(0.071, 0.113)) + time * temporalDrift;
    const float animatedVariation = 1.0 + sin(driftPhase) * 0.5 * blockInstability * saturate(temporalDrift);
    const float wavePhase = float(blockCoordinate.x * blockCoordinate.y) / 1000000.0
        + time * temporalDrift * 0.5;
    const float waveVariation = mix(
        1.0,
        1.0 + (1.0 + cos(wavePhase)) * 5.0,
        saturate(blockWave)
    );

    return max(staticVariation * animatedVariation * waveVariation, 0.000001);
}

fragment half4 postFragment(
    VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    texture2d<half, access::read> coefficientTexture [[texture(FragmentTextureCustom0)]]
) {
    const uint2 textureSize = uint2(
        coefficientTexture.get_width(),
        coefficientTexture.get_height()
    );
    const uint2 coordinate = min(
        uint2(in.texcoord * float2(textureSize)),
        textureSize - 1
    );
    const half4 source = coefficientTexture.read(coordinate);

    const float strength = saturate(uniforms.strength);

    const uint blockSize = uint(clamp(uniforms.blockSize, 2, 32));
    const uint2 frequencyCoordinate = coordinate % blockSize;
    const uint2 blockCoordinate = coordinate / blockSize;
    const uint2 blockOrigin = blockCoordinate * blockSize;
    const uint2 blockExtent = min(uint2(blockSize), textureSize - blockOrigin);

    const float2 frequencyDenominator = max(float2(blockExtent) - 1.0, 1.0);
    const float2 normalizedFrequencyCoordinate =
        float2(frequencyCoordinate) / frequencyDenominator;
    const float normalizedFrequency =
        length(normalizedFrequencyCoordinate) * 0.70710678118;

    const float protection = mix(
        1.0 - saturate(uniforms.lowFrequencyProtect),
        1.0,
        smoothstep(0.0, 0.35, normalizedFrequency)
    );
    const float frequencyWeight =
        1.0 + max(uniforms.frequencyBias, 0.0) * normalizedFrequency * normalizedFrequency;
    const float strengthWeight = exp2(strength * 6.0) - 1.0;
    const float blockVariation = dctCorruptionBlockVariation(
        blockCoordinate,
        saturate(uniforms.blockInstability),
        saturate(uniforms.blockWave),
        max(uniforms.temporalDrift, 0.0),
        uniforms.time
    );

    const float3 quantizationStep =
        max(uniforms.quantization, 0.0)
        * strengthWeight
        * frequencyWeight
        * blockVariation
        * max(uniforms.channelStrength, float3(0.0))
        * max(protection, 0.000001);

    const bool isDC = all(frequencyCoordinate == uint2(0));
    const float3 dcLevelShiftChannels = saturate(float3(
        uniforms.dcLevelShiftChannel1,
        uniforms.dcLevelShiftChannel2,
        uniforms.dcLevelShiftChannel3
    ));
    const float3 dcLevelShift = isDC
        ? uniforms.dcLevelShift
            * sqrt(float(blockExtent.x * blockExtent.y))
            * dcLevelShiftChannels
        : float3(0.0);
    const float3 coefficients = float3(source.rgb) - dcLevelShift;
    const float3 shouldCorrupt = step(float3(0.000001), quantizationStep)
        * float3(strength > 0.000001 ? 1.0 : 0.0);
    const float3 safeQuantizationStep = max(quantizationStep, float3(0.000001));
    const float3 coefficientBias = uniforms.coefficientBias * safeQuantizationStep;
    const float3 biasedCoefficients = coefficients + coefficientBias;
    const float3 corruptedCoefficients =
        floor(biasedCoefficients / safeQuantizationStep) * safeQuantizationStep
        - coefficientBias * saturate(uniforms.biasReturn);
    const float3 mixedCoefficients = mix(coefficients, corruptedCoefficients, strength);
    const float3 outputCoefficients =
        mix(coefficients, mixedCoefficients, shouldCorrupt)
        + dcLevelShift * saturate(uniforms.dcLevelReturn);

    return half4(half3(outputCoefficients), source.a);
}
