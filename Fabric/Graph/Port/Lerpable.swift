//
//  Lerpable.swift
//  Fabric
//

import Foundation
import simd

/// A value that can be linearly interpolated between two endpoints by a
/// 0...1 parameter. Deliberately not constrained on stdlib `SIMD` (unlike
/// VectorTweenNode<Value>) so Float can conform too.
public protocol Lerpable
{
    static func lerp(_ a: Self, _ b: Self, _ t: Float) -> Self
}

extension Float: Lerpable
{
    public static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float
    {
        simd_mix(a, b, t)
    }
}

extension simd_float2: Lerpable
{
    public static func lerp(_ a: simd_float2, _ b: simd_float2, _ t: Float) -> simd_float2
    {
        simd_mix(a, b, simd_float2(repeating: t))
    }
}

extension simd_float3: Lerpable
{
    public static func lerp(_ a: simd_float3, _ b: simd_float3, _ t: Float) -> simd_float3
    {
        simd_mix(a, b, simd_float3(repeating: t))
    }
}

extension simd_float4: Lerpable
{
    public static func lerp(_ a: simd_float4, _ b: simd_float4, _ t: Float) -> simd_float4
    {
        simd_mix(a, b, simd_float4(repeating: t))
    }
}

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
