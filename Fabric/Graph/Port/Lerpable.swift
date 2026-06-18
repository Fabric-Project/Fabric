//
//  Lerpable.swift
//  Fabric
//

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
