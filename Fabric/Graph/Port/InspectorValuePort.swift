//
//  InspectorValuePort.swift
//  Fabric
//

import Foundation
import Satin
import simd

/// Builds an inlet port for a generic `Value` that is editable in the inspector
/// where a matching `Parameter` type exists (Float / Vector2 / Vector3 /
/// Vector4), and falls back to a plain `NodePort` for value types without one.
///
/// This lets a single generic node (registered per type, e.g.
/// `ArrayWithCountNode<Float>.self`) expose an inspector-editable value inlet
/// without needing a hand-written concrete subclass per type.
func makeInspectorValuePort<Value: PortValueRepresentable>(
    _ type: Value.Type,
    name: String,
    description: String
) -> Port
{
    if Value.self == Float.self {
        return ParameterPort(parameter: FloatParameter(name, 0.0, .inputfield, description))
    } else if Value.self == simd_float2.self {
        return ParameterPort(parameter: Float2Parameter(name, .zero, .inputfield, description))
    } else if Value.self == simd_float3.self {
        return ParameterPort(parameter: Float3Parameter(name, .zero, .inputfield, description))
    } else if Value.self == simd_float4.self {
        return ParameterPort(parameter: Float4Parameter(name, .zero, .inputfield, description))
    } else {
        return NodePort<Value>(name: name, kind: .Inlet, description: description)
    }
}
