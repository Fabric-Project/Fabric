//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Exclusion blend mode

#define BLEND_FUNC(a, b) blendExclusion(a, b)

#include "MixTemplate.msl"
