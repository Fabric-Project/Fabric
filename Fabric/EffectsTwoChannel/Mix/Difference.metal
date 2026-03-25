//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Difference blend mode

#define BLEND_FUNC(a, b) blendDifference(a, b)

#include "MixTemplate.msl"
