//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Subtract blend mode

#define BLEND_FUNC(a, b) blendSubtract(a, b)

#include "MixTemplate.msl"
