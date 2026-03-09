//
//  TestCard.metal
//  Fabric
//
//  Created by Claude on 3/1/26.
//

#include <metal_stdlib>
using namespace metal;

struct TestCardFlags {
    uint showBorder;
    uint showGreys;
    uint showDiagonals;
    uint showCircle;
    uint showGrid;
    uint gridSpacing;
};

kernel void testCardGenerate
(
    uint2 gid [[thread_position_in_grid]],
    texture2d<float, access::write> outTex [[texture(0)]],
    constant TestCardFlags &flags [[buffer(0)]]
)
{
    uint w = outTex.get_width();
    uint h = outTex.get_height();

    if (gid.x >= w || gid.y >= h) return;

    // Start with black background
    float4 color = float4(0.0, 0.0, 0.0, 1.0);

    // Greyscale cells (drawn first as background)
    if (flags.showGreys && gid.x >= 2 && gid.x < w - 2 && gid.y >= 2 && gid.y < h - 2)
    {
        uint innerX = gid.x - 2;
        uint innerY = gid.y - 2;
        uint innerW = w - 4;
        uint innerH = h - 4;

        uint col = innerX * 5 / innerW;
        uint row = innerY * 2 / innerH;
        col = min(col, 4u);
        row = min(row, 1u);

        uint cellIndex = row * 5 + col;
        float gray = 1.0 - float(cellIndex) / 9.0;
        color = float4(gray, gray, gray, 1.0);
    }

    // Grid
    if (flags.showGrid && flags.gridSpacing > 0)
    {
        uint spacing = flags.gridSpacing;
        if (gid.x % spacing == 0 || gid.y % spacing == 0)
        {
            color = float4(1.0, 1.0, 1.0, 1.0);
        }
    }

    // Diagonals
    if (flags.showDiagonals)
    {
        float fx = float(gid.x);
        float fy = float(gid.y);
        float fw = float(w - 1);
        float fh = float(h - 1);
        float diagLen = sqrt(fw * fw + fh * fh);

        float dist1 = abs(fy * fw - fx * fh) / diagLen;
        float dist2 = abs(fy * fw - (fw - fx) * fh) / diagLen;
        if (dist1 < 0.5 || dist2 < 0.5)
        {
            color = float4(1.0, 1.0, 1.0, 1.0);
        }
    }

    // Circle
    if (flags.showCircle)
    {
        float cx = float(w) * 0.5;
        float cy = float(h) * 0.5;
        float radius = float(min(w, h)) * 0.5;
        float distFromCenter = length(float2(float(gid.x) - cx, float(gid.y) - cy));
        if (abs(distFromCenter - radius) < 0.5)
        {
            color = float4(1.0, 1.0, 1.0, 1.0);
        }
    }

    // Border (drawn last, on top)
    if (flags.showBorder)
    {
        if (gid.x == 0 || gid.x == w - 1 || gid.y == 0 || gid.y == h - 1)
        {
            color = float4(1.0, 1.0, 1.0, 1.0);
        }
        else if (gid.x == 1 || gid.x == w - 2 || gid.y == 1 || gid.y == h - 2)
        {
            color = float4(0.0, 0.0, 0.0, 1.0);
        }
    }

    outTex.write(color, gid);
}
