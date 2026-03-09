//
//  TestCard.metal
//  Fabric
//
//  Created by Claude on 3/1/26.
//

#include <metal_stdlib>
using namespace metal;

#include "../lygia/sdf/lineSDF.msl"

struct TestCardFlags {
    uint showBorder;
    uint showGreys;
    uint showDiagonals;
    uint showCircle;
    uint showGrid;
    uint gridSpacing;
    uint showText;
    uint textX;
    uint textY;
    uint textW;
    uint textH;
};

kernel void testCardGenerate
(
    uint2 gid [[thread_position_in_grid]],
    texture2d<float, access::write> outTex [[texture(0)]],
    texture2d<float, access::read> textTex [[texture(1)]],
    constant TestCardFlags &flags [[buffer(0)]]
)
{
    uint w = outTex.get_width();
    uint h = outTex.get_height();

    if (gid.x >= w || gid.y >= h) return;

    float4 color = float4(0.0, 0.0, 0.0, 1.0);

    // Greyscale cells (5x2 grid, white-to-black ramp)
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

    // Grid (integer modulo — pixel-exact)
    if (flags.showGrid && flags.gridSpacing > 0)
    {
        uint spacing = flags.gridSpacing;
        if (gid.x % spacing == 0 || gid.y % spacing == 0)
        {
            color = float4(1.0, 1.0, 1.0, 1.0);
        }
    }

    // Diagonals via lygia lineSDF (pixel-space, 1px hard edge)
    if (flags.showDiagonals)
    {
        float2 p = float2(gid);
        float2 tl = float2(0.0);
        float2 tr = float2(float(w - 1), 0.0);
        float2 bl = float2(0.0, float(h - 1));
        float2 br = float2(float(w - 1), float(h - 1));

        float d1 = lineSDF(p, tl, br);
        float d2 = lineSDF(p, tr, bl);

        if (d1 < 0.5 || d2 < 0.5)
        {
            color = float4(1.0, 1.0, 1.0, 1.0);
        }
    }

    // Circle (pixel-space distance, 1px hard edge)
    if (flags.showCircle)
    {
        float2 center = float2(w, h) * 0.5;
        float radius = float(min(w, h)) * 0.5;
        float dist = length(float2(gid) - center);

        if (abs(dist - radius) < 0.5)
        {
            color = float4(1.0, 1.0, 1.0, 1.0);
        }
    }

    // Text label (composited from CPU-rendered texture)
    if (flags.showText)
    {
        uint tx = gid.x - flags.textX;
        uint ty = gid.y - flags.textY;
        if (gid.x >= flags.textX && tx < flags.textW &&
            gid.y >= flags.textY && ty < flags.textH)
        {
            float4 texel = textTex.read(uint2(tx, ty));
            color = mix(color, texel, texel.a);
        }
    }

    // Border (pixel-exact: 1px white + 1px black inset)
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
