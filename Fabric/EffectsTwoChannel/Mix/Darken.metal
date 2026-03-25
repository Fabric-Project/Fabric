//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Darken blend mode

#define BLEND_FUNC(a, b) blendDarken(a, b)

#include "MixTemplate.msl"
