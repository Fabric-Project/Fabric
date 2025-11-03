//
//  InvertCompute.metal
//  
//
//  Created by Anton Marini on 10/29/25.
//

#include <metal_stdlib>
using namespace metal;

typedef struct {
} Uniforms;


kernel void Reset
(
     uint2 gid [[thread_position_in_grid]],
     texture2d<float, access::read> inTex [[texture( ComputeTextureCustom0 )]],
     texture2d<float, access::write> outTex [[texture( ComputeTextureCustom1 )]],
     constant Uniforms &uniforms [[buffer( ComputeBufferUniforms )]]
) {
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;

    float4 color = inTex.read(gid);
    color.rgb = 1.0 - color.rgb;
    outTex.write(color, gid);
}

kernel void Update
(
     uint2 gid [[thread_position_in_grid]],
     texture2d<float, access::read> inTex [[texture( ComputeTextureCustom0 )]],
     texture2d<float, access::write> outTex [[texture( ComputeTextureCustom1 )]],
     constant Uniforms &uniforms [[buffer( ComputeBufferUniforms )]]
) {
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;

    float4 color = inTex.read(gid);
    color.rgb = 1.0 - color.rgb;
//    color.a = 1.0;
    outTex.write(color, gid);
}

