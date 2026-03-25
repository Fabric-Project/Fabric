//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Negation blend mode

#define BLEND_FUNC(a, b) blendNegation(a, b)

#include "MixTemplate.msl"

