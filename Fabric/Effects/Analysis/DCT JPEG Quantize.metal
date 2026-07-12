//
//  DCT JPEG Quantize.metal
//  Fabric
//
// description: Quantizes 8x8 DCT coefficients with JPEG-style luma and chroma tables
//

#include <metal_stdlib>
using namespace metal;

typedef struct {
    int blockSize;              // slider, 2, 32, 8, Block Size
    float quality;              // slider, 1.0, 100.0, 35.0, Quality
    float amount;               // slider, 0.0, 1.0, 1.0, Amount
    float lumaScale;            // slider, 0.0, 4.0, 1.0, Luma Scale
    float chromaScale;          // slider, 0.0, 8.0, 1.0, Chroma Scale
    float dcScale;              // slider, 0.0, 4.0, 0.25, DC Scale
    float highFrequencyBoost;   // slider, 0.0, 4.0, 1.0, High Frequency Boost
    float deadZone;             // slider, 0.0, 2.0, 0.0, Dead Zone
    float3 channelStrength;     // slider, 0.0, 4.0, 1.0, Channel Strength
} PostUniforms;

constant float jpegLumaQuantizationTable[64] = {
    16.0, 11.0, 10.0, 16.0, 24.0, 40.0, 51.0, 61.0,
    12.0, 12.0, 14.0, 19.0, 26.0, 58.0, 60.0, 55.0,
    14.0, 13.0, 16.0, 24.0, 40.0, 57.0, 69.0, 56.0,
    14.0, 17.0, 22.0, 29.0, 51.0, 87.0, 80.0, 62.0,
    18.0, 22.0, 37.0, 56.0, 68.0, 109.0, 103.0, 77.0,
    24.0, 35.0, 55.0, 64.0, 81.0, 104.0, 113.0, 92.0,
    49.0, 64.0, 78.0, 87.0, 103.0, 121.0, 120.0, 101.0,
    72.0, 92.0, 95.0, 98.0, 112.0, 100.0, 103.0, 99.0
};

constant float jpegChromaQuantizationTable[64] = {
    17.0, 18.0, 24.0, 47.0, 99.0, 99.0, 99.0, 99.0,
    18.0, 21.0, 26.0, 66.0, 99.0, 99.0, 99.0, 99.0,
    24.0, 26.0, 56.0, 99.0, 99.0, 99.0, 99.0, 99.0,
    47.0, 66.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0,
    99.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0,
    99.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0,
    99.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0,
    99.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0
};

static float jpegQualityScale(float quality)
{
    const float safeQuality = clamp(quality, 1.0, 100.0);
    return safeQuality < 50.0
        ? 5000.0 / safeQuality
        : 200.0 - safeQuality * 2.0;
}

static uint jpegTableIndex(uint2 frequencyCoordinate, uint2 blockExtent)
{
    const float2 frequencyDenominator = max(float2(blockExtent) - 1.0, 1.0);
    const uint2 tableCoordinate = min(
        uint2(round(float2(frequencyCoordinate) / frequencyDenominator * 7.0)),
        uint2(7)
    );
    return tableCoordinate.y * 8u + tableCoordinate.x;
}

static float jpegQuantizationStep(float tableValue,
                                  float quality,
                                  float channelScale,
                                  float frequencyWeight,
                                  bool isDC,
                                  float dcScale)
{
    const float scaledTableValue = max(
        floor((tableValue * jpegQualityScale(quality) + 50.0) / 100.0),
        1.0
    );
    const float coefficientScale = scaledTableValue / 255.0;
    const float dcWeight = isDC ? max(dcScale, 0.0) : 1.0;
    return coefficientScale
        * max(channelScale, 0.0)
        * max(frequencyWeight, 0.0)
        * dcWeight;
}

static float jpegQuantizeCoefficient(float coefficient, float quantizationStep, float deadZone)
{
    if (quantizationStep <= 0.000001) {
        return coefficient;
    }

    const float magnitude = abs(coefficient);
    const float threshold = quantizationStep * max(deadZone, 0.0);
    if (magnitude < threshold) {
        return 0.0;
    }

    return round(coefficient / quantizationStep) * quantizationStep;
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

    const uint blockSize = uint(clamp(uniforms.blockSize, 2, 32));
    const uint2 frequencyCoordinate = coordinate % blockSize;
    const uint2 blockCoordinate = coordinate / blockSize;
    const uint2 blockOrigin = blockCoordinate * blockSize;
    const uint2 blockExtent = min(uint2(blockSize), textureSize - blockOrigin);
    const bool isDC = all(frequencyCoordinate == uint2(0));
    const uint tableIndex = jpegTableIndex(frequencyCoordinate, blockExtent);

    const float2 frequencyDenominator = max(float2(blockExtent) - 1.0, 1.0);
    const float2 normalizedFrequencyCoordinate =
        float2(frequencyCoordinate) / frequencyDenominator;
    const float normalizedFrequency =
        length(normalizedFrequencyCoordinate) * 0.70710678118;
    const float frequencyWeight =
        1.0 + max(uniforms.highFrequencyBoost, 0.0)
            * normalizedFrequency
            * normalizedFrequency;

    const float3 coefficients = float3(source.rgb);
    const float3 channelScale = max(uniforms.channelStrength, float3(0.0))
        * float3(max(uniforms.lumaScale, 0.0),
                 max(uniforms.chromaScale, 0.0),
                 max(uniforms.chromaScale, 0.0));
    const float3 quantizationStep = float3(
        jpegQuantizationStep(
            jpegLumaQuantizationTable[tableIndex],
            uniforms.quality,
            channelScale.x,
            frequencyWeight,
            isDC,
            uniforms.dcScale
        ),
        jpegQuantizationStep(
            jpegChromaQuantizationTable[tableIndex],
            uniforms.quality,
            channelScale.y,
            frequencyWeight,
            isDC,
            uniforms.dcScale
        ),
        jpegQuantizationStep(
            jpegChromaQuantizationTable[tableIndex],
            uniforms.quality,
            channelScale.z,
            frequencyWeight,
            isDC,
            uniforms.dcScale
        )
    );

    const float3 quantizedCoefficients = float3(
        jpegQuantizeCoefficient(coefficients.x, quantizationStep.x, uniforms.deadZone),
        jpegQuantizeCoefficient(coefficients.y, quantizationStep.y, uniforms.deadZone),
        jpegQuantizeCoefficient(coefficients.z, quantizationStep.z, uniforms.deadZone)
    );
    const float amount = saturate(uniforms.amount);

    return half4(half3(mix(coefficients, quantizedCoefficients, amount)), source.a);
}
