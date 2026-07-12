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
    uint4 channelSubsampleX;
    uint4 channelSubsampleY;
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

static uint dctSubsampledLocalCoordinate(uint coordinate,
                                         uint extent,
                                         uint subsampleFactor)
{
    const uint safeExtent = max(extent, 1u);
    const uint factor = max(subsampleFactor, 1u);
    const uint subsampledCoordinate = (coordinate / factor) * factor;

    return min(subsampledCoordinate, safeExtent - 1u);
}

static float4 dctReadSubsampledChannels(texture2d<half, access::read> source,
                                        uint2 blockOrigin,
                                        uint2 localPosition,
                                        uint2 blockExtent,
                                        uint4 subsampleX,
                                        uint4 subsampleY)
{
    const uint redX = dctSubsampledLocalCoordinate(localPosition.x, blockExtent.x, subsampleX.x);
    const uint redY = dctSubsampledLocalCoordinate(localPosition.y, blockExtent.y, subsampleY.x);
    const uint greenX = dctSubsampledLocalCoordinate(localPosition.x, blockExtent.x, subsampleX.y);
    const uint greenY = dctSubsampledLocalCoordinate(localPosition.y, blockExtent.y, subsampleY.y);
    const uint blueX = dctSubsampledLocalCoordinate(localPosition.x, blockExtent.x, subsampleX.z);
    const uint blueY = dctSubsampledLocalCoordinate(localPosition.y, blockExtent.y, subsampleY.z);
    const uint alphaX = dctSubsampledLocalCoordinate(localPosition.x, blockExtent.x, subsampleX.w);
    const uint alphaY = dctSubsampledLocalCoordinate(localPosition.y, blockExtent.y, subsampleY.w);

    return float4(
        source.read(blockOrigin + uint2(redX, redY)).r,
        source.read(blockOrigin + uint2(greenX, greenY)).g,
        source.read(blockOrigin + uint2(blueX, blueY)).b,
        source.read(blockOrigin + uint2(alphaX, alphaY)).a
    );
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
    const uint2 blockExtent = uint2(blockWidth, blockHeight);
    const uint intermediateIndex = localPosition.y * blockSize + localPosition.x;

    threadgroup float4 intermediate[DCT_MAXIMUM_BLOCK_SIZE * DCT_MAXIMUM_BLOCK_SIZE];

    float4 horizontalCoefficient = 0.0;
    if (localPosition.x < blockWidth && localPosition.y < blockHeight) {
        for (uint sampleX = 0; sampleX < blockWidth; sampleX++) {
            const float4 color = dctReadSubsampledChannels(
                source,
                blockOrigin,
                uint2(sampleX, localPosition.y),
                blockExtent,
                uniforms.channelSubsampleX,
                uniforms.channelSubsampleY
            );
            horizontalCoefficient += color * dctBasisValue(
                basis,
                blockWidth,
                localPosition.x,
                sampleX
            );
        }
    }
    intermediate[intermediateIndex] = horizontalCoefficient;

    threadgroup_barrier(mem_flags::mem_threadgroup);

    if (localPosition.x < blockWidth && localPosition.y < blockHeight) {
        float4 coefficient = 0.0;
        for (uint sampleY = 0; sampleY < blockHeight; sampleY++) {
            coefficient += intermediate[sampleY * blockSize + localPosition.x]
                * dctBasisValue(basis, blockHeight, localPosition.y, sampleY);
        }

        destination.write(
            half4(coefficient),
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
    const uint redLocalX = dctSubsampledLocalCoordinate(
        localPosition.x,
        blockWidth,
        uniforms.channelSubsampleX.x
    );
    const uint greenLocalX = dctSubsampledLocalCoordinate(
        localPosition.x,
        blockWidth,
        uniforms.channelSubsampleX.y
    );
    const uint blueLocalX = dctSubsampledLocalCoordinate(
        localPosition.x,
        blockWidth,
        uniforms.channelSubsampleX.z
    );
    const uint alphaLocalX = dctSubsampledLocalCoordinate(
        localPosition.x,
        blockWidth,
        uniforms.channelSubsampleX.w
    );
    const uint redLocalY = dctSubsampledLocalCoordinate(
        localPosition.y,
        blockHeight,
        uniforms.channelSubsampleY.x
    );
    const uint greenLocalY = dctSubsampledLocalCoordinate(
        localPosition.y,
        blockHeight,
        uniforms.channelSubsampleY.y
    );
    const uint blueLocalY = dctSubsampledLocalCoordinate(
        localPosition.y,
        blockHeight,
        uniforms.channelSubsampleY.z
    );
    const uint alphaLocalY = dctSubsampledLocalCoordinate(
        localPosition.y,
        blockHeight,
        uniforms.channelSubsampleY.w
    );

    threadgroup float4 intermediate[DCT_MAXIMUM_BLOCK_SIZE * DCT_MAXIMUM_BLOCK_SIZE];

    float4 horizontalValue = 0.0;
    if (localPosition.x < blockWidth && localPosition.y < blockHeight) {
        for (uint frequencyX = 0; frequencyX < blockWidth; frequencyX++) {
            const float4 coefficient = float4(
                source.read(blockOrigin + uint2(frequencyX, localPosition.y))
            );
            const float4 basisValue = float4(
                dctBasisValue(basis, blockWidth, frequencyX, redLocalX),
                dctBasisValue(basis, blockWidth, frequencyX, greenLocalX),
                dctBasisValue(basis, blockWidth, frequencyX, blueLocalX),
                dctBasisValue(basis, blockWidth, frequencyX, alphaLocalX)
            );
            horizontalValue += coefficient * basisValue;
        }
    }
    intermediate[intermediateIndex] = horizontalValue;

    threadgroup_barrier(mem_flags::mem_threadgroup);

    if (localPosition.x < blockWidth && localPosition.y < blockHeight) {
        float4 color = 0.0;
        for (uint frequencyY = 0; frequencyY < blockHeight; frequencyY++) {
            const float4 basisValue = float4(
                dctBasisValue(basis, blockHeight, frequencyY, redLocalY),
                dctBasisValue(basis, blockHeight, frequencyY, greenLocalY),
                dctBasisValue(basis, blockHeight, frequencyY, blueLocalY),
                dctBasisValue(basis, blockHeight, frequencyY, alphaLocalY)
            );
            color += intermediate[frequencyY * blockSize + localPosition.x] * basisValue;
        }

        destination.write(
            half4(color),
            blockOrigin + localPosition
        );
    }
}
