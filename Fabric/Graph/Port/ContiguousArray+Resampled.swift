//
//  ContiguousArray+Resampled.swift
//  Fabric
//

import Foundation
import Satin

extension ContiguousArray where Element: Lerpable
{
    /// This array stretched or shrunk to `count` elements by index-domain linear
    /// interpolation: the first and last elements stay put and every output
    /// element samples the source at the same relative position. Handles both
    /// decimation and upsampling with one code path. Empty when the array is
    /// empty or `count` is not positive.
    public func resampled(count: Int) -> ContiguousArray<Element>
    {
        guard let first = self.first, count > 0 else { return [] }
        if count == 1 { return [first] }

        let lastIndex = Float(self.count - 1)
        let tDivisor  = Float(count - 1)       // safe: count >= 2 past the count == 1 guard above
        var output = ContiguousArray<Element>(repeating: first, count: count)

        let concurrentThreshold = 128
        if count >= concurrentThreshold {
            output.withUnsafeMutableBufferPointer { buf in
                DispatchQueue.concurrentPerform(iterations: count) { i in
                    let sourcePosition = (Float(i) / tDivisor) * lastIndex
                    let i0 = Int(sourcePosition)
                    let i1 = Swift.min(i0 + 1, self.count - 1)
                    buf[i] = Element.lerp(self[i0], self[i1], sourcePosition - Float(i0))
                }
            }
        } else {
            for i in 0..<count {
                let sourcePosition = (Float(i) / tDivisor) * lastIndex
                let i0 = Int(sourcePosition)
                let i1 = Swift.min(i0 + 1, self.count - 1)
                output[i] = Element.lerp(self[i0], self[i1], sourcePosition - Float(i0))
            }
        }
        return output
    }
}
