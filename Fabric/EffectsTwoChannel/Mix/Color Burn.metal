//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Color Burn blend mode

#define BLEND_FUNC(a, b) blendColorBurn(a, b)

#include "MixTemplate.msl"
