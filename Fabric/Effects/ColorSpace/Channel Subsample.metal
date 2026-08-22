//
//  Channel Subsample.metal
//  Fabric
//
// description: Subsamples each image channel on an independent pixel grid
//

#include <metal_stdlib>
using namespace metal;

typedef struct {
    int channel1Horizontal; // slider, 1, 32, 1, Channel 1 Horizontal
    int channel1Vertical;   // slider, 1, 32, 1, Channel 1 Vertical
    int channel2Horizontal; // slider, 1, 32, 1, Channel 2 Horizontal
    int channel2Vertical;   // slider, 1, 32, 1, Channel 2 Vertical
    int channel3Horizontal; // slider, 1, 32, 1, Channel 3 Horizontal
    int channel3Vertical;   // slider, 1, 32, 1, Channel 3 Vertical
    int channel4Horizontal; // slider, 1, 32, 1, Channel 4 Horizontal
    int channel4Vertical;   // slider, 1, 32, 1, Channel 4 Vertical
    float amount;           // slider, 0.0, 1.0, 1.0, Amount
} PostUniforms;

static uint2 subsampledCoordinate(
    uint2 coordinate,
    uint2 textureSize,
    int horizontalFactor,
    int verticalFactor
) {
    const uint horizontal = uint(max(horizontalFactor, 1));
    const uint vertical = uint(max(verticalFactor, 1));
    const uint2 factor = uint2(horizontal, vertical);
    const uint2 blockOrigin = (coordinate / factor) * factor;
    const uint2 blockExtent = max(
        min(factor, textureSize - blockOrigin),
        uint2(1)
    );
    const uint2 centerOffset = min(blockExtent / 2, blockExtent - 1);

    return min(blockOrigin + centerOffset, textureSize - 1);
}

fragment half4 postFragment(
    VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    texture2d<half, access::read> renderTex [[texture(FragmentTextureCustom0)]]
) {
    const uint2 textureSize = uint2(
        renderTex.get_width(),
        renderTex.get_height()
    );
    const uint2 coordinate = min(
        uint2(in.texcoord * float2(textureSize)),
        textureSize - 1
    );

    const half4 source = renderTex.read(coordinate);

    const uint2 channel1Coordinate = subsampledCoordinate(
        coordinate,
        textureSize,
        uniforms.channel1Horizontal,
        uniforms.channel1Vertical
    );
    const uint2 channel2Coordinate = subsampledCoordinate(
        coordinate,
        textureSize,
        uniforms.channel2Horizontal,
        uniforms.channel2Vertical
    );
    const uint2 channel3Coordinate = subsampledCoordinate(
        coordinate,
        textureSize,
        uniforms.channel3Horizontal,
        uniforms.channel3Vertical
    );
    const uint2 channel4Coordinate = subsampledCoordinate(
        coordinate,
        textureSize,
        uniforms.channel4Horizontal,
        uniforms.channel4Vertical
    );

    const half4 subsampled = half4(
        renderTex.read(channel1Coordinate).r,
        renderTex.read(channel2Coordinate).g,
        renderTex.read(channel3Coordinate).b,
        renderTex.read(channel4Coordinate).a
    );

    return mix(source, subsampled, half(clamp(uniforms.amount, 0.0, 1.0)));
}
