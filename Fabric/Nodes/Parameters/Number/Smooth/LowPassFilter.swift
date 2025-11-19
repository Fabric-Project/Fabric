
//
//  LowPassFilter.swift
//
//  Created by Giraudeau Philippe @ Inria Bordeaux Sud-Ouest, France on 02/09/2019.
//  Copyright © 2019 Inria Bordeaux Sud-Ouest. All rights reserved.
//

import Foundation

public class LowPassFilter {
    var y: Double
    var a: Double = 0.0
    var s: Double
    var initialized: Bool
    
    init(alpha:Double, initval:Double = 0.0) {
        y = initval; s = initval
        initialized = false
        setAlpha(alpha: alpha)
    }
    
    public func setAlpha(alpha: Double){
        if ((alpha <= 0.0) || (alpha > 1.0)) {
            print("Alpha should be in range [0.0..1.0]!alpha=%lf",alpha)
        } else {
            self.a = alpha }
    }
    
    public func filter(value:Double) -> Double {
        var result:Double
        if (initialized){
        result = a * value + (1.0 - a) * s
        }else {
            result = value
            initialized = true
        }
        y = value
        s = result
        return result;
    }
    
    public func filterWithAlpha(value:Double, alpha:Double) -> Double {
        setAlpha(alpha: alpha)
        return filter(value: value)
    }
    
    public func hasLastRawValue() -> Bool {
        return initialized
    }
    
    public func lastRawValue() -> Double {
        return y
    }
}
