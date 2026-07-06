//
//  DCTTransform.metal
//  Fabric
//
//  Block-based, orthonormal DCT-II and inverse DCT-III transforms.
//

#include <metal_stdlib>
using namespace metal;

#define DCT_MAXIMUM_BLOCK_SIZE 32

struct DCTUniforms {
    uint blockSize;
};

static uint dctBasisOffset(uint dimension)
{
    uint precedingDimension = dimension - 1;
    return precedingDimension * dimension * (2 * dimension - 1) / 6;
}

static float dctBasisValue(constant float *basis,
                           uint dimension,
                           uint frequency,
                           uint sample)
{
    return basis[dctBasisOffset(dimension) + frequency * dimension + sample];
}

kernel void dctForward(
    texture2d<half, access::read> source [[texture(0)]],
    texture2d<half, access::write> destination [[texture(1)]],
    constant float *basis [[buffer(0)]],
    constant DCTUniforms &uniforms [[buffer(1)]],
    uint2 localPosition [[thread_position_in_threadgroup]],
    uint2 threadgroupPosition [[threadgroup_position_in_grid]])
{
    const uint blockSize = uniforms.blockSize;
    const uint2 blockOrigin = threadgroupPosition * blockSize;
    const uint blockWidth = min(blockSize, source.get_width() - blockOrigin.x);
    const uint blockHeight = min(blockSize, source.get_height() - blockOrigin.y);
    const uint intermediateIndex = localPosition.y * blockSize + localPosition.x;

    threadgroup float4 intermediate[DCT_MAXIMUM_BLOCK_SIZE * DCT_MAXIMUM_BLOCK_SIZE];

    float3 horizontalCoefficient = 0.0;
    if (localPosition.x < blockWidth && localPosition.y < blockHeight) {
        for (uint sampleX = 0; sampleX < blockWidth; sampleX++) {
            float3 color = float3(source.read(blockOrigin + uint2(sampleX, localPosition.y)).rgb);
            horizontalCoefficient += color * dctBasisValue(
                basis,
                blockWidth,
                localPosition.x,
                sampleX
            );
        }
    }
    intermediate[intermediateIndex] = float4(horizontalCoefficient, 0.0);

    threadgroup_barrier(mem_flags::mem_threadgroup);

    if (localPosition.x < blockWidth && localPosition.y < blockHeight) {
        float3 coefficient = 0.0;
        for (uint sampleY = 0; sampleY < blockHeight; sampleY++) {
            coefficient += intermediate[sampleY * blockSize + localPosition.x].rgb
                * dctBasisValue(basis, blockHeight, localPosition.y, sampleY);
        }

        destination.write(
            half4(half3(coefficient), 1.0h),
            blockOrigin + localPosition
        );
    }
}

kernel void dctInverse(
    texture2d<half, access::read> source [[texture(0)]],
    texture2d<half, access::write> destination [[texture(1)]],
    constant float *basis [[buffer(0)]],
    constant DCTUniforms &uniforms [[buffer(1)]],
    uint2 localPosition [[thread_position_in_threadgroup]],
    uint2 threadgroupPosition [[threadgroup_position_in_grid]])
{
    const uint blockSize = uniforms.blockSize;
    const uint2 blockOrigin = threadgroupPosition * blockSize;
    const uint blockWidth = min(blockSize, source.get_width() - blockOrigin.x);
    const uint blockHeight = min(blockSize, source.get_height() - blockOrigin.y);
    const uint intermediateIndex = localPosition.y * blockSize + localPosition.x;

    threadgroup float4 intermediate[DCT_MAXIMUM_BLOCK_SIZE * DCT_MAXIMUM_BLOCK_SIZE];

    float3 horizontalValue = 0.0;
    if (localPosition.x < blockWidth && localPosition.y < blockHeight) {
        for (uint frequencyX = 0; frequencyX < blockWidth; frequencyX++) {
            float3 coefficient = float3(
                source.read(blockOrigin + uint2(frequencyX, localPosition.y)).rgb
            );
            horizontalValue += coefficient * dctBasisValue(
                basis,
                blockWidth,
                frequencyX,
                localPosition.x
            );
        }
    }
    intermediate[intermediateIndex] = float4(horizontalValue, 0.0);

    threadgroup_barrier(mem_flags::mem_threadgroup);

    if (localPosition.x < blockWidth && localPosition.y < blockHeight) {
        float3 color = 0.0;
        for (uint frequencyY = 0; frequencyY < blockHeight; frequencyY++) {
            color += intermediate[frequencyY * blockSize + localPosition.x].rgb
                * dctBasisValue(basis, blockHeight, frequencyY, localPosition.y);
        }

        destination.write(
            half4(half3(color), 1.0h),
            blockOrigin + localPosition
        );
    }
}
