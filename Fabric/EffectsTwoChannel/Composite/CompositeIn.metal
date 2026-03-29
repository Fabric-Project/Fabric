//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Porter-Duff In compositing

#define COMPOSITE_FUNC(a, b) compositeSourceIn(a, b)

#include "CompositeTemplate.msl"
