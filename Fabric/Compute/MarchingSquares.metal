//
//  File.metal
//  
//
//  Created by Anton Marini on 10/29/25.
//

#include <metal_stdlib>
using namespace metal;

// Input:  texture(0) = mask (float / normalized), read
// Output: buffer(0)  = segments float4(x0,y0,x1,y1)[]
//         buffer(1)  = atomic uint counter
// Uniforms: buffer(2) optional uniforms containing Iso (float)

struct Uniforms {
    float Iso;
    uint MaxSegments;
//    float2 Size; // not strictly needed
};

inline float sample(texture2d<float, access::read> tex, int2 p)
{
    // Clamp to texture bounds
    int w = tex.get_width();
    int h = tex.get_height();
    p.x = clamp(p.x, 0, w-1);
    p.y = clamp(p.y, 0, h-1);
    return tex.read(uint2(p)).r;
}

// Interpolate edge positions in pixel space
// Edges: E0:(c00-c10) top, E1:(c10-c11) right, E2:(c11-c01) bottom, E3:(c01-c00) left

inline float2 lerpPos(int2 a, float va, int2 b, float vb, float iso) {
    float denom = max(fabs(vb - va), 1e-6f);
    float t = clamp((iso - va) / denom, 0.0f, 1.0f);
    return float2(a) + t * float2(b - a);
}

kernel void Update(const uint2 gid [[thread_position_in_grid]],
                   texture2d<float, access::read> mask  [[texture(0)]],
                   device float4* segments              [[buffer(1)]],
                   device atomic_uint* segCounter       [[buffer(2)]],
                   constant Uniforms& uniforms            [[buffer(0)]] )
{
    // DEBUG
//    if (gid.x == 0 && gid.y == 0) {
//        uint base = atomic_fetch_add_explicit(segCounter, 1u, memory_order_relaxed);
////       segCounter[0] = 1;                     // <-- should read back 123 on CPU
//       segments[0] = float4(1,2,3,4);     // <-- optional: also write a segment
//     }
    
    // Each thread handles one cell (skip last row/col)
    uint w = mask.get_width();
    uint h = mask.get_height();
    if (gid.x >= w-1 || gid.y >= h-1) return;

    float iso = uniforms.Iso;

    // Cell corners (x,y):
    //  c00 = (x, y), c10 = (x+1, y)
    //  c01 = (x, y+1), c11 = (x+1, y+1)
    int2 c00 = int2(gid.x,     gid.y);
    int2 c10 = int2(gid.x + 1, gid.y);
    int2 c01 = int2(gid.x,     gid.y + 1);
    int2 c11 = int2(gid.x + 1, gid.y + 1);

    float v00 = sample(mask, c00);
    float v10 = sample(mask, c10);
    float v01 = sample(mask, c01);
    float v11 = sample(mask, c11);

    // Build case index (bit per corner)
    // bit0=c00, bit1=c10, bit2=c11, bit3=c01 (one of the common conventions)
    uint idx = 0;
    idx |= (v00 > iso) ? 1u : 0u;
    idx |= (v10 > iso) ? 2u : 0u;
    idx |= (v11 > iso) ? 4u : 0u;
    idx |= (v01 > iso) ? 8u : 0u;

    if (idx == 0u || idx == 15u) {
        return; // no crossings
    }

    float2 e[4];
    e[0] = lerpPos(c00, v00, c10, v10, iso); // top
    e[1] = lerpPos(c10, v10, c11, v11, iso); // right
    e[2] = lerpPos(c11, v11, c01, v01, iso); // bottom
    e[3] = lerpPos(c01, v01, c00, v00, iso); // left

    // Emit up to 2 segments per cell per standard marching-squares table
    // We’ll handle the ambiguous 5/10 by a simple consistent rule: connect (e0-e3) & (e1-e2)
    // Table encoded as pairs of edge indices; -1 means no segment.
    int2 segs[2];
    segs[0] = int2(-1, -1);
    segs[1] = int2(-1, -1);

    switch (idx) {
        case 1:  segs[0] = int2(3,0); break;
        case 2:  segs[0] = int2(0,1); break;
        case 3:  segs[0] = int2(3,1); break;
        case 4:  segs[0] = int2(1,2); break;
        case 5:  segs[0] = int2(3,0); segs[1]=int2(1,2); break; // ambiguous
        case 6:  segs[0] = int2(0,2); break;
        case 7:  segs[0] = int2(3,2); break;
        case 8:  segs[0] = int2(2,3); break;
        case 9:  segs[0] = int2(0,2); break;
        case 10: segs[0] = int2(0,1); segs[1]=int2(2,3); break; // ambiguous
        case 11: segs[0] = int2(1,2); break;
        case 12: segs[0] = int2(3,1); break;
        case 13: segs[0] = int2(0,1); break;
        case 14: segs[0] = int2(3,0); break;
        default: break;
    }

    // Calculate total segments needed for this cell
    uint segCount = 0u;
    if (idx != 0u && idx != 15u) {
        segCount = (idx == 5u || idx == 10u) ? 2u : 1u;
    }
    
    if (segCount > 0u) {
        // Reserve contiguous memory space ONCE for all segments from this cell
        uint base = atomic_fetch_add_explicit(segCounter, segCount, memory_order_relaxed);
        
        // Check bounds after getting the base index
        if (base + segCount > uniforms.MaxSegments) return;
        
        // Write first segment
        if (segs[0].x >= 0) {
            float2 a = e[segs[0].x];
            float2 b = e[segs[0].y];
            segments[base] = float4(a, b);
        }
        
        // Write second segment if it exists, offset by 1
        if (segs[1].x >= 0) {
            float2 a = e[segs[1].x];
            float2 b = e[segs[1].y];
            segments[base + 1u] = float4(a, b); // Use base + 1u
        }
    }
    
//    // Append segments
//    if (segs[0].x >= 0) {
////        uint base = atomic_fetch_add_explicit(segCounter, 1u, memory_order_relaxed);
//        uint segCount = (idx == 0u || idx == 15u) ? 0u :
//        (idx == 5u || idx == 10u) ? 2u : 1u;
//        
//        if (segCount == 0u) return;
//        
//        uint base = atomic_fetch_add_explicit(segCounter, segCount, memory_order_relaxed);
//        if (base + segCount > uniforms.MaxSegments) return; // prevent OOB writes
//        
//        float2 a = e[segs[0].x];
//        float2 b = e[segs[0].y];
//        segments[base] = float4(a, b);
//    }
//    if (segs[1].x >= 0) {
////        uint base = atomic_fetch_add_explicit(segCounter, 1u, memory_order_relaxed);
//        uint segCount = (idx == 0u || idx == 15u) ? 0u :
//        (idx == 5u || idx == 10u) ? 2u : 1u;
//        
//        if (segCount == 0u) return;
//        
//        uint base = atomic_fetch_add_explicit(segCounter, segCount, memory_order_relaxed);
//        if (base + segCount > uniforms.MaxSegments) return; // prevent OOB writes
//        
//        float2 a = e[segs[1].x];
//        float2 b = e[segs[1].y];
//        segments[base] = float4(a, b);
//    }
}
