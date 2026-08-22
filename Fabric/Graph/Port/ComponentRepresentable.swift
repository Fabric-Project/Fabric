//
//  ComponentRepresentable.swift
//  Fabric
//

import simd

/// A value that can be built from, and decomposed into, an ordered list of
/// named components (e.g. simd_float3 <-> X, Y, Z). Backs the generic
/// Compose/Decompose node family so one generic node class can build named
/// per-component ports for any conforming Value, instead of one hand-written
/// class per vector width.
public protocol ComponentRepresentable
{
    associatedtype Component: PortValueRepresentable

    static var componentLabels: [String] { get }

    init(componentValues: [Component])
    var componentValues: [Component] { get }
}

extension simd_float2: ComponentRepresentable
{
    public static var componentLabels: [String] { ["X", "Y"] }

    public init(componentValues: [Float])
    {
        self.init(componentValues[0], componentValues[1])
    }

    public var componentValues: [Float] { [x, y] }
}

extension simd_float3: ComponentRepresentable
{
    public static var componentLabels: [String] { ["X", "Y", "Z"] }

    public init(componentValues: [Float])
    {
        self.init(componentValues[0], componentValues[1], componentValues[2])
    }

    public var componentValues: [Float] { [x, y, z] }
}

extension simd_float4: ComponentRepresentable
{
    public static var componentLabels: [String] { ["X", "Y", "Z", "W"] }

    public init(componentValues: [Float])
    {
        self.init(componentValues[0], componentValues[1], componentValues[2], componentValues[3])
    }

    public var componentValues: [Float] { [x, y, z, w] }
}
