//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Averages two images equally

#define BLEND_FUNC(a, b) blendAverage(a, b)

#include "MixTemplate.msl"
