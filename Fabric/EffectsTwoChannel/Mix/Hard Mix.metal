//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Hard Mix blend mode

#define BLEND_FUNC(a, b) blendHardMix(a, b)

#include "MixTemplate.msl"
