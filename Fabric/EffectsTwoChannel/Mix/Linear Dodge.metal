//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Linear Dodge blend mode

#define BLEND_FUNC(a, b) blendLinearDodge(a, b)

#include "MixTemplate.msl"
