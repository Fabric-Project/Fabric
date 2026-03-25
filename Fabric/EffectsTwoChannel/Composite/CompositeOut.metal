//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Porter-Duff Out compositing

#define COMPOSITE_FUNC(a, b) compositeSourceOut(a, b)

#include "CompositeTemplate.msl"
