//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Linear Burn blend mode

#define BLEND_FUNC(a, b) blendLinearBurn(a, b)

#include "MixTemplate.msl"
