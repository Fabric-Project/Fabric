//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Luminosity blend mode

#define BLEND_FUNC(a, b) blendLuminosity(a, b)

#include "MixTemplate.msl"
