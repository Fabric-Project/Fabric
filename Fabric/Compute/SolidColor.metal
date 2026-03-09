#include <metal_stdlib>
using namespace metal;

kernel void solidColorFill(
    uint2 gid [[thread_position_in_grid]],
    texture2d<float, access::write> outTex [[texture(0)]],
    constant float4 &color [[buffer(0)]]
)
{
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) { return; }
    outTex.write(color, gid);
}
