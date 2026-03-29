//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Porter-Duff Atop compositing

#define COMPOSITE_FUNC(a, b) compositeSourceAtop(a, b)

#include "CompositeTemplate.msl"
