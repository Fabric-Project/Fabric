//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Soft Light blend mode

#define BLEND_FUNC(a, b) blendSoftLight(a, b)

#include "MixTemplate.msl"
