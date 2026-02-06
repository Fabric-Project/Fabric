//
//  SuperShape.h
//  SuperShapes
//
//  Created by Reza Ali on 9/7/20.
//  Copyright © 2020 Reza Ali. All rights reserved.
//

#pragma once

#ifndef SuperShapeGenerator_h
#define SuperShapeGenerator_h

#if __has_include(<Satin/SatinCore.h>)
#include <Satin/SatinCore.h>
#elif __has_include(<SatinCore/SatinCore.h>)
#include <SatinCore/SatinCore.h>
#elif __has_include("SatinCore.h")
#include "SatinCore.h"
#else
#error "Cannot find SatinCore.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif


GeometryData generateSuperShapeGeometryData(float r1, float a1, float b1, float m1, float n11,
                                            float n21, float n31, float r2, float a2, float b2,
                                            float m2, float n12, float n22, float n32, int resTheta,
                                            int resPhi);


#ifdef __cplusplus
}
#endif

#endif /* SuperShapeGenerator_h */
