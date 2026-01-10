//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//

float sdCircle( float2 p, float r )
{
    return length(p) - r;
}

#include "../../lygia/sdf/circleSDF.msl"
#include "sdfPre.msl"

    float sdf = sdCircle(st_f, 1.0);

    return half4(sdf);
}
