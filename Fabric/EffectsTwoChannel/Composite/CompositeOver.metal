//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Porter-Duff Over compositing

#define COMPOSITE_FUNC(a, b) compositeSourceOver(a, b)

#include "CompositeTemplate.msl"
