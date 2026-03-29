//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//
// description: Porter-Duff Xor compositing

#define COMPOSITE_FUNC(a, b) compositeXor(a, b)

#include "CompositeTemplate.msl"
