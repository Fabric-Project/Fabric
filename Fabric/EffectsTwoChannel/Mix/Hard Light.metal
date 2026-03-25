//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Hard Light blend mode

#define BLEND_FUNC(a, b) blendHardLight(a, b)

#include "MixTemplate.msl"
