//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Lighten blend mode

#define BLEND_FUNC(a, b) blendLighten(a, b)

#include "MixTemplate.msl"
