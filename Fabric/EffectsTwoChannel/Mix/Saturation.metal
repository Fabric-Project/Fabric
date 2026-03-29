//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Saturation blend mode

#define BLEND_FUNC(a, b) blendSaturation(a, b)

#include "MixTemplate.msl"
