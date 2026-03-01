//
//  TestCard.metal
//  Fabric
//
//  Created by Claude on 3/1/26.
//

#include <metal_stdlib>
using namespace metal;

kernel void testCardGenerate
(
    uint2 gid [[thread_position_in_grid]],
    texture2d<float, access::write> outTex [[texture(0)]]
)
{
    uint w = outTex.get_width();
    uint h = outTex.get_height();

    if (gid.x >= w || gid.y >= h) return;

    bool onLine = false;

    // Border: top, bottom, left, right edges
    if (gid.x == 0 || gid.x == w - 1 || gid.y == 0 || gid.y == h - 1)
    {
        onLine = true;
    }

    // Diagonals: point-to-line distance test for continuous 1px lines
    if (!onLine)
    {
        float fx = float(gid.x);
        float fy = float(gid.y);
        float fw = float(w - 1);
        float fh = float(h - 1);

        // Diagonal TL(0,0) -> BR(fw,fh): line direction (fw, fh)
        // Distance = |fy * fw - fx * fh| / length(fw, fh)
        float len = sqrt(fw * fw + fh * fh);
        float dist1 = abs(fy * fw - fx * fh) / len;
        if (dist1 < 0.5) onLine = true;

        // Diagonal TR(fw,0) -> BL(0,fh): flip x
        if (!onLine)
        {
            float dist2 = abs(fy * fw - (fw - fx) * fh) / len;
            if (dist2 < 0.5) onLine = true;
        }
    }

    float4 color = onLine ? float4(1.0, 1.0, 1.0, 1.0) : float4(0.0, 0.0, 0.0, 1.0);
    outTex.write(color, gid);
}
