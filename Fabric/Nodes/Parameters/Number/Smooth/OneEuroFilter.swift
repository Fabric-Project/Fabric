//
//  OneEuroFilter.swift
//
//  Created by Giraudeau Philippe @ Inria Bordeaux Sud-Ouest, France on 02/09/2019.
//  Copyright © 2019 Inria Bordeaux Sud-Ouest. All rights reserved.
//

import Foundation


///Helper function used to init LowPassFilter properties (x, dx) in the OneEuroFilter object
fileprivate func initAlpha(cutoff:Double, frequence freq:Double) -> Double {
    let te:Double = 1.0 / freq
    let tau:Double = 1.0 / (2.0 * Double.pi * cutoff)
    return 1.0 / (1.0 + tau / te)
}

public class OneEuroFilter {
    var freq: Double
    var mincutoff: Double
    var beta: Double
    var dcutoff: Double
    var x:LowPassFilter
    var dx:LowPassFilter
    var lasttime: Double
    
    var currValue: Double
    var prevValue: Double
    
    init(freq:Double,  mincutoff:Double = 1.0,  beta:Double = 0.0,  dcutoff:Double = 1.0) {
        
        lasttime = -1.0
        currValue = 0.0
        prevValue = currValue
        self.freq = freq
        self.mincutoff = mincutoff
        self.beta = beta
        self.dcutoff = dcutoff
        
        
        x = LowPassFilter(alpha: initAlpha(cutoff: mincutoff, frequence: freq))
        dx = LowPassFilter(alpha: initAlpha(cutoff: dcutoff, frequence: freq))
        
        
    }
    
    func alpha(_ cutoff:Double) -> Double {
        let te:Double = 1.0 / freq
        let tau:Double = 1.0 / (2.0 * Double.pi * cutoff)
        return 1.0 / (1.0 + tau / te)
    }
    
    func setFrequency(_ f:Double) {
        if (f <= 0.0) {
            print("freq =" ,f, ". It should be > 0")
            return
        }
        freq = f
    }
    
    func setMinCutoff(_ mc:Double)
    {
        if (mc <= 0.0){
            print("mincutoff should be > 0");
            return
        }
        mincutoff = mc
    }
    
    
    func setDerivateCutoff(_ dc:Double)
    {
        if (dc <= 0.0){
            print("dcutoff should be > 0")
            return
        }
        dcutoff = dc
    }
    
    public func UpdateParams(_ freq:Double, _ mincutoff:Double, _ beta:Double, _ dcutoff:Double){
        setFrequency(freq)
        setMinCutoff(mincutoff)
        self.beta = beta
        setDerivateCutoff(dcutoff)
        x.setAlpha(alpha: alpha(mincutoff))
        dx.setAlpha(alpha: alpha(dcutoff))
    }
    
    public func UpdateParams(freq: Double, mincutoff: Double, beta: Double, dcutoff: Double)
    {
        setFrequency(freq)
        setMinCutoff(mincutoff)
        self.beta = beta
        setDerivateCutoff(dcutoff)
        x.setAlpha(alpha: alpha(mincutoff))
        dx.setAlpha(alpha: alpha(dcutoff))
    }
    
    public func Filter(_ value:Double, timestamp:Double = -1.0) -> Double {
        prevValue = currValue
    
        // update the sampling frequency based on timestamps
        if (lasttime != -1.0 && timestamp != -1.0){
            freq = 1.0 / (timestamp - lasttime)
        }
        lasttime = timestamp
        // estimate the current variation per second
        let dvalue = x.hasLastRawValue() ? (value - x.lastRawValue()) * freq : 0.0 // FIXME: 0.0 or value?
        let edvalue = dx.filterWithAlpha(value: dvalue, alpha: alpha(dcutoff))
        // use it to update the cutoff frequency
        let cutoff = mincutoff + beta * abs(edvalue)
        // filter the given value
        currValue = x.filterWithAlpha(value: value , alpha: alpha(cutoff))
    
        return currValue
    }
}
