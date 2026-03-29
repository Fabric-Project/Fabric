//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Color Dodge blend mode

#define BLEND_FUNC(a, b) blendColorDodge(a, b)

#include "MixTemplate.msl"
