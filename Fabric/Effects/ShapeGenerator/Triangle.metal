//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//


float sdEquilateralTriangle( float2 p, float r )
{
    const float k = sqrt(3.0);
    p.y += 0.08;
    p.x = abs(p.x) - r;
    p.y = p.y + r/k;
    if( p.x+k*p.y>0.0 ) p = float2(p.x-k*p.y,-k*p.x-p.y)/2.0;
    p.x -= clamp( p.x, -2.0*r, 0.0 );
    return -length(p)*sign(p.y);
}

#include "../../lygia/sdf/triSDF.msl"
#include "sdfPre.msl"

    float sdf = sdEquilateralTriangle(st_f, 1.0);

    //sdf = opRound(sdf, uniforms.round);

    return half4(sdf);
}
