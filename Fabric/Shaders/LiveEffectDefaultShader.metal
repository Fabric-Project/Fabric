//
//  LiveEffectDefaultShader.metal
//  Fabric
//
//  Created by Codex on 3/4/26.
//

#include <metal_stdlib>
using namespace metal;

typedef struct {
    float amount; // slider, 0.0, 1.0, 1.0, Amount
} PostUniforms;

fragment half4 postFragment(VertexData in [[stage_in]],
                            constant PostUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
                            texture2d<half, access::sample> inputTexture [[texture(FragmentTextureCustom0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    half4 color = inputTexture.sample(s, in.texcoord);
    return mix(half4(0.0), color, half(uniforms.amount));
}
