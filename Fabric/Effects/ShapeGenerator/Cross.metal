//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//


float sdRoundedX(float2 p, float w, float r )
{
    p = abs(p);
    return length(p-min(p.x+p.y,w)*0.5) - r;
}

float sdCross(float2 p, float2 b, float r ) 
{
    p = abs(p); p = (p.y>p.x) ? p.yx : p.xy;
    float2  q = p - b;
    float k = max(q.y,q.x);
    float2  w = (k>0.0) ? q : float2(b.y-p.x,-k);
    return sign(k)*length(max(w,0.0)) + r;
}

#include "../../lygia/sdf/crossSDF.msl"

#include "sdfPre.msl"

    float sdf = sdCross(st_f, float2(1.0, 0.2), 0.0);

    return half4(sdf);
}
