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

    // 1px white border
    if (gid.x == 0 || gid.x == w - 1 || gid.y == 0 || gid.y == h - 1)
    {
        outTex.write(float4(1.0, 1.0, 1.0, 1.0), gid);
        return;
    }

    // 1px black spacer
    if (gid.x == 1 || gid.x == w - 2 || gid.y == 1 || gid.y == h - 2)
    {
        outTex.write(float4(0.0, 0.0, 0.0, 1.0), gid);
        return;
    }

    // Inner region starts at (2,2), size is (w-4) x (h-4)
    uint innerX = gid.x - 2;
    uint innerY = gid.y - 2;
    uint innerW = w - 4;
    uint innerH = h - 4;

    // 5x2 grid: column from x, row from y
    uint col = innerX * 5 / innerW;
    uint row = innerY * 2 / innerH;

    // Clamp to valid range
    col = min(col, 4u);
    row = min(row, 1u);

    // 10 cells (row-major), step from white (1.0) to black (0.0)
    uint cellIndex = row * 5 + col;
    float gray = 1.0 - float(cellIndex) / 9.0;

    // Diagonals over the full image
    float fx = float(gid.x);
    float fy = float(gid.y);
    float fw = float(w - 1);
    float fh = float(h - 1);
    float diagLen = sqrt(fw * fw + fh * fh);

    float dist1 = abs(fy * fw - fx * fh) / diagLen;
    float dist2 = abs(fy * fw - (fw - fx) * fh) / diagLen;
    bool onDiagonal = (dist1 < 0.5) || (dist2 < 0.5);

    // Circle centered on image, radius = min(w,h)/2
    float cx = float(w) * 0.5;
    float cy = float(h) * 0.5;
    float radius = float(min(w, h)) * 0.5;
    float distFromCenter = length(float2(fx - cx, fy - cy));
    bool onCircle = abs(distFromCenter - radius) < 0.5;

    if (onDiagonal || onCircle)
    {
        outTex.write(float4(1.0, 1.0, 1.0, 1.0), gid);
        return;
    }

    outTex.write(float4(gray, gray, gray, 1.0), gid);
}
