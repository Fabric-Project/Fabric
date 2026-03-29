//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Additive blend mode

#define BLEND_FUNC(a, b) blendAdd(a, b)

#include "MixTemplate.msl"
