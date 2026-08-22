//
//  ImageResample.metal
//  Fabric
//

#include <metal_stdlib>
using namespace metal;

enum ResamplingMethod : uint {
    ResamplingMethodBicubic = 2,
    ResamplingMethodLanczos2 = 3,
    ResamplingMethodLanczos3 = 4,
    ResamplingMethodArea = 5,
};

struct ResamplingUniforms {
    uint method;
};

static float cubicWeight(float value)
{
    constexpr float coefficient = -0.5;
    float distance = abs(value);

    if (distance < 1.0) {
        return (coefficient + 2.0) * distance * distance * distance
            - (coefficient + 3.0) * distance * distance
            + 1.0;
    }
    if (distance < 2.0) {
        return coefficient * distance * distance * distance
            - 5.0 * coefficient * distance * distance
            + 8.0 * coefficient * distance
            - 4.0 * coefficient;
    }
    return 0.0;
}

static float sinc(float value)
{
    if (abs(value) < 0.000001) {
        return 1.0;
    }

    float angle = M_PI_F * value;
    return sin(angle) / angle;
}

static float lanczosWeight(float value, float radius)
{
    float distance = abs(value);
    return distance < radius ? sinc(value) * sinc(value / radius) : 0.0;
}

static float reconstructionWeight(uint method, float value)
{
    switch (method) {
    case ResamplingMethodLanczos2:
        return lanczosWeight(value, 2.0);
    case ResamplingMethodLanczos3:
        return lanczosWeight(value, 3.0);
    default:
        return cubicWeight(value);
    }
}

static float reconstructionRadius(uint method)
{
    return method == ResamplingMethodLanczos3 ? 3.0 : 2.0;
}

static float4 areaSample(
    texture2d<float, access::read> source,
    uint destinationIndex,
    uint fixedCoordinate,
    uint destinationLength,
    bool horizontal)
{
    uint sourceLength = horizontal ? source.get_width() : source.get_height();
    float scale = float(sourceLength) / float(destinationLength);
    float sourceStart = float(destinationIndex) * scale;
    float sourceEnd = float(destinationIndex + 1) * scale;
    int firstSample = int(floor(sourceStart));
    int lastSample = int(ceil(sourceEnd)) - 1;

    float4 accumulatedColor = 0.0;
    float accumulatedWeight = 0.0;

    for (int sampleIndex = firstSample; sampleIndex <= lastSample; sampleIndex++) {
        float sampleStart = float(sampleIndex);
        float overlap = max(
            0.0,
            min(sourceEnd, sampleStart + 1.0) - max(sourceStart, sampleStart)
        );
        uint clampedSample = uint(clamp(sampleIndex, 0, int(sourceLength) - 1));
        uint2 sourceCoordinate = horizontal
            ? uint2(clampedSample, fixedCoordinate)
            : uint2(fixedCoordinate, clampedSample);

        accumulatedColor += source.read(sourceCoordinate) * overlap;
        accumulatedWeight += overlap;
    }

    return accumulatedWeight > 0.0
        ? accumulatedColor / accumulatedWeight
        : float4(0.0);
}

static float4 reconstructedSample(
    texture2d<float, access::read> source,
    uint destinationIndex,
    uint fixedCoordinate,
    uint destinationLength,
    uint method,
    bool horizontal)
{
    uint sourceLength = horizontal ? source.get_width() : source.get_height();
    float scale = float(sourceLength) / float(destinationLength);
    float filterScale = max(scale, 1.0);
    float center = (float(destinationIndex) + 0.5) * scale - 0.5;
    float support = reconstructionRadius(method) * filterScale;
    int firstSample = int(ceil(center - support));
    int lastSample = int(floor(center + support));

    float4 accumulatedColor = 0.0;
    float accumulatedWeight = 0.0;

    for (int sampleIndex = firstSample; sampleIndex <= lastSample; sampleIndex++) {
        float weight = reconstructionWeight(
            method,
            (float(sampleIndex) - center) / filterScale
        );
        uint clampedSample = uint(clamp(sampleIndex, 0, int(sourceLength) - 1));
        uint2 sourceCoordinate = horizontal
            ? uint2(clampedSample, fixedCoordinate)
            : uint2(fixedCoordinate, clampedSample);

        accumulatedColor += source.read(sourceCoordinate) * weight;
        accumulatedWeight += weight;
    }

    return abs(accumulatedWeight) > 0.000001
        ? accumulatedColor / accumulatedWeight
        : float4(0.0);
}

kernel void resampleNearest(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> destination [[texture(1)]],
    uint2 position [[thread_position_in_grid]])
{
    if (position.x >= destination.get_width() || position.y >= destination.get_height()) {
        return;
    }

    float2 scale = float2(source.get_width(), source.get_height())
        / float2(destination.get_width(), destination.get_height());
    float2 sourcePosition = (float2(position) + 0.5) * scale - 0.5;
    int2 nearestPosition = int2(floor(sourcePosition + 0.5));
    nearestPosition = clamp(
        nearestPosition,
        int2(0),
        int2(int(source.get_width()) - 1, int(source.get_height()) - 1)
    );

    destination.write(source.read(uint2(nearestPosition)), position);
}

kernel void resampleBilinear(
    texture2d<float, access::sample> source [[texture(0)]],
    texture2d<float, access::write> destination [[texture(1)]],
    uint2 position [[thread_position_in_grid]])
{
    if (position.x >= destination.get_width() || position.y >= destination.get_height()) {
        return;
    }

    constexpr sampler linearSampler(
        coord::normalized,
        address::clamp_to_edge,
        filter::linear
    );
    float2 uv = (float2(position) + 0.5)
        / float2(destination.get_width(), destination.get_height());
    destination.write(source.sample(linearSampler, uv), position);
}

kernel void resampleHorizontal(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> destination [[texture(1)]],
    constant ResamplingUniforms &uniforms [[buffer(0)]],
    uint2 position [[thread_position_in_grid]])
{
    if (position.x >= destination.get_width() || position.y >= destination.get_height()) {
        return;
    }

    float4 color = uniforms.method == ResamplingMethodArea
        ? areaSample(
            source,
            position.x,
            position.y,
            destination.get_width(),
            true
        )
        : reconstructedSample(
            source,
            position.x,
            position.y,
            destination.get_width(),
            uniforms.method,
            true
        );

    destination.write(color, position);
}

kernel void resampleVertical(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> destination [[texture(1)]],
    constant ResamplingUniforms &uniforms [[buffer(0)]],
    uint2 position [[thread_position_in_grid]])
{
    if (position.x >= destination.get_width() || position.y >= destination.get_height()) {
        return;
    }

    float4 color = uniforms.method == ResamplingMethodArea
        ? areaSample(
            source,
            position.y,
            position.x,
            destination.get_height(),
            false
        )
        : reconstructedSample(
            source,
            position.y,
            position.x,
            destination.get_height(),
            uniforms.method,
            false
        );

    destination.write(color, position);
}
