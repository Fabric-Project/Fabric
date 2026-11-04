//
//  PortType+Factory.swift
//  Fabric
//
//  Created by Anton Marini on 12/22/25.
//

import Foundation
import Satin
import simd

extension PortType
{
    /// A port carrying an editable parameter of its own, or nil for a type that
    /// has none to offer. Only an inlet gets one: an outlet's value is the
    /// node's to write.
    ///
    /// Which types can carry a parameter is `ParameterValueType`'s to
    /// say, save for Color. Color and Vector4 are both simd_float4, so the type
    /// cannot tell them apart; the colorpicker control is what makes the port
    /// read back as .Color (see `ParameterPort.portType`).
    private func makeFreshParameterPort(name: String, kind: PortKind, description: String, id: UUID) -> Port?
    {
        guard kind == .Inlet else { return nil }

        if case .Color = self
        {
            return ParameterPort(parameter: Float4Parameter(name, simd_float4(0, 0, 0, 1), .colorpicker, description), id: id)
        }

        guard let editableType = self.type as? any ParameterValueType.Type else { return nil }

        return editableType.makeDefaultParameterPort(name: name, description: description, id: id)
    }

    /// Creates a new port of this type. An inlet whose type can be a parameter
    /// (see `ParameterValueType`) is a parameter port, so it holds a value of its
    /// own when unwired; every other port is plain.
    public func makeFreshPort(name: String, kind: PortKind, description: String = "", id: UUID = UUID()) -> Port
    {
        if let parameterPort = makeFreshParameterPort(name: name, kind: kind, description: description, id: id)
        {
            return parameterPort
        }

        let port = makeFreshPlainPort(name: name, kind: kind, description: description, id: id)
        if kind == .Inlet, let restingValue
        {
            port.restoreValue(from: restingValue)
        }
        return port
    }

    /// The value a plain inlet of this type starts at: its leaf value type's
    /// `defaultValue`, so an unwired Quaternion inlet holds identity. A
    /// collection or virtual inlet rests at nothing, so an unwired one still
    /// reads as unwired. A parameter port's parameter supplies its own default
    /// instead.
    internal var restingValue: PortValue?
    {
        guard Self.scalarCases.contains(self),
              let valueType = self.type as? any PortValueRepresentable.Type
        else { return nil }

        return valueType.defaultValue?.toPortValue()
    }

    /// A port of this type with no parameter, whatever the type.
    internal func makePlainPort(name: String, kind: PortKind, description: String = "", id: UUID = UUID()) -> Port
    {
        makeFreshPlainPort(name: name, kind: kind, description: description, id: id)
    }

    private func makeFreshPlainPort(name: String, kind: PortKind, description: String, id: UUID) -> Port
    {
        switch self
        {
        case .Bool:       return NodePort<Bool>(name: name, kind: kind, description: description, id: id)
        case .Int:        return NodePort<Int>(name: name, kind: kind, description: description, id: id)
        case .Float:      return NodePort<Float>(name: name, kind: kind, description: description, id: id)
        case .String:     return NodePort<String>(name: name, kind: kind, description: description, id: id)
        case .Vector2:    return NodePort<simd_float2>(name: name, kind: kind, description: description, id: id)
        case .Vector3:    return NodePort<simd_float3>(name: name, kind: kind, description: description, id: id)
        case .Vector4:    return NodePort<simd_float4>(name: name, kind: kind, description: description, id: id)
        case .Color:      return ColorNodePort(name: name, kind: kind, description: description, id: id)
        case .Quaternion: return NodePort<simd_quatf>(name: name, kind: kind, description: description, id: id)
        case .Transform:  return NodePort<simd_float4x4>(name: name, kind: kind, description: description, id: id)
        case .Geometry:   return NodePort<Satin.Geometry>(name: name, kind: kind, description: description, id: id)
        case .Material:   return NodePort<Satin.Material>(name: name, kind: kind, description: description, id: id)
        case .Image:      return NodePort<FabricImage>(name: name, kind: kind, description: description, id: id)
        case .NumericVirtual: return NumericVirtualPort(name: name, kind: kind, description: description, id: id)
        case .Virtual:    return NodePort<PortValue>(name: name, kind: kind, description: description, id: id)
        case .Array(portType: let elementType):
            return Self.makeFreshArrayPort(elementType: elementType, name: name, kind: kind, description: description, id: id)
        case .Dictionary(valueType: let valueType):
            return Self.makeFreshDictionaryPort(dictionaryType: self, valueType: valueType, name: name, kind: kind, description: description, id: id)
        }
    }

    private static func makeFreshArrayPort(elementType: PortType, name: String, kind: PortKind, description: String, id: UUID) -> Port
    {
        switch elementType
        {
        case .Bool:        return NodePort<ContiguousArray<Bool>>(name: name, kind: kind, description: description, id: id)
        case .Int:         return NodePort<ContiguousArray<Int>>(name: name, kind: kind, description: description, id: id)
        case .Float:       return NodePort<ContiguousArray<Float>>(name: name, kind: kind, description: description, id: id)
        case .String:      return NodePort<ContiguousArray<String>>(name: name, kind: kind, description: description, id: id)
        case .Vector2:     return NodePort<ContiguousArray<simd_float2>>(name: name, kind: kind, description: description, id: id)
        case .Vector3:     return NodePort<ContiguousArray<simd_float3>>(name: name, kind: kind, description: description, id: id)
        case .Vector4:     return NodePort<ContiguousArray<simd_float4>>(name: name, kind: kind, description: description, id: id)
        case .Color: return ColorArrayNodePort(name: name, kind: kind, description: description, id: id)
        case .Quaternion:  return NodePort<ContiguousArray<simd_quatf>>(name: name, kind: kind, description: description, id: id)
        case .Transform:   return NodePort<ContiguousArray<simd_float4x4>>(name: name, kind: kind, description: description, id: id)
        case .Geometry:    return NodePort<ContiguousArray<Satin.Geometry>>(name: name, kind: kind, description: description, id: id)
        case .Material:    return NodePort<ContiguousArray<Satin.Material>>(name: name, kind: kind, description: description, id: id)
        case .Image:       return NodePort<ContiguousArray<FabricImage>>(name: name, kind: kind, description: description, id: id)
        default:           return DeclaredNodePort<ContiguousArray<PortValue>>(declaredPortType: .Array(portType: elementType), name: name, kind: kind, description: description, id: id)
        }
    }

    private static func makeFreshDictionaryPort(dictionaryType: PortType, valueType: PortType, name: String, kind: PortKind, description: String, id: UUID) -> Port
    {
        switch valueType
        {
        case .Bool:        return NodePort<Dictionary<String, Bool>>(name: name, kind: kind, description: description, id: id)
        case .Int:         return NodePort<Dictionary<String, Int>>(name: name, kind: kind, description: description, id: id)
        case .Float:       return NodePort<Dictionary<String, Float>>(name: name, kind: kind, description: description, id: id)
        case .String:      return NodePort<Dictionary<String, String>>(name: name, kind: kind, description: description, id: id)
        case .Vector2:     return NodePort<Dictionary<String, simd_float2>>(name: name, kind: kind, description: description, id: id)
        case .Vector3:     return NodePort<Dictionary<String, simd_float3>>(name: name, kind: kind, description: description, id: id)
        case .Vector4:     return NodePort<Dictionary<String, simd_float4>>(name: name, kind: kind, description: description, id: id)
        case .Color:       return DeclaredNodePort<Dictionary<String, simd_float4>>(declaredPortType: dictionaryType, name: name, kind: kind, description: description, id: id)
        case .Quaternion:  return NodePort<Dictionary<String, simd_quatf>>(name: name, kind: kind, description: description, id: id)
        case .Transform:   return NodePort<Dictionary<String, simd_float4x4>>(name: name, kind: kind, description: description, id: id)
        case .Geometry:    return NodePort<Dictionary<String, Satin.Geometry>>(name: name, kind: kind, description: description, id: id)
        case .Material:    return NodePort<Dictionary<String, Satin.Material>>(name: name, kind: kind, description: description, id: id)
        case .Image:       return NodePort<Dictionary<String, FabricImage>>(name: name, kind: kind, description: description, id: id)
        case .Array(portType: let elementType):
            return Self.makeFreshDictionaryOfArrayPort(dictionaryType: dictionaryType, elementType: elementType, name: name, kind: kind, description: description, id: id)
        case .Virtual:
            return NodePort<Dictionary<String, PortValue>>(name: name, kind: kind, description: description, id: id)
        default:
            return DeclaredNodePort<Dictionary<String, PortValue>>(declaredPortType: dictionaryType, name: name, kind: kind, description: description, id: id)
        }
    }

    private static func makeFreshDictionaryOfArrayPort(dictionaryType: PortType, elementType: PortType, name: String, kind: PortKind, description: String, id: UUID) -> Port
    {
        switch elementType
        {
        case .Bool:        return NodePort<Dictionary<String, ContiguousArray<Bool>>>(name: name, kind: kind, description: description, id: id)
        case .Int:         return NodePort<Dictionary<String, ContiguousArray<Int>>>(name: name, kind: kind, description: description, id: id)
        case .Float:       return NodePort<Dictionary<String, ContiguousArray<Float>>>(name: name, kind: kind, description: description, id: id)
        case .String:      return NodePort<Dictionary<String, ContiguousArray<String>>>(name: name, kind: kind, description: description, id: id)
        case .Vector2:     return NodePort<Dictionary<String, ContiguousArray<simd_float2>>>(name: name, kind: kind, description: description, id: id)
        case .Vector3:     return NodePort<Dictionary<String, ContiguousArray<simd_float3>>>(name: name, kind: kind, description: description, id: id)
        case .Vector4:     return NodePort<Dictionary<String, ContiguousArray<simd_float4>>>(name: name, kind: kind, description: description, id: id)
        case .Color:       return DeclaredNodePort<Dictionary<String, ContiguousArray<simd_float4>>>(declaredPortType: dictionaryType, name: name, kind: kind, description: description, id: id)
        case .Quaternion:  return NodePort<Dictionary<String, ContiguousArray<simd_quatf>>>(name: name, kind: kind, description: description, id: id)
        case .Transform:   return NodePort<Dictionary<String, ContiguousArray<simd_float4x4>>>(name: name, kind: kind, description: description, id: id)
        case .Geometry:    return NodePort<Dictionary<String, ContiguousArray<Satin.Geometry>>>(name: name, kind: kind, description: description, id: id)
        case .Material:    return NodePort<Dictionary<String, ContiguousArray<Satin.Material>>>(name: name, kind: kind, description: description, id: id)
        case .Image:       return NodePort<Dictionary<String, ContiguousArray<FabricImage>>>(name: name, kind: kind, description: description, id: id)
        default:           return DeclaredNodePort<Dictionary<String, PortValue>>(declaredPortType: dictionaryType, name: name, kind: kind, description: description, id: id)
        }
    }

    /// The port for an existing parameter — a shader's, a material's, a compute
    /// processor's — where `makeFreshPort` is the port for a type. Nil for a
    /// parameter whose value type cannot be a parameter port. Given an `id`, for
    /// a port taking another's place, the port takes it and keys the parameter
    /// to it.
    public static func port(for parameter: any Parameter, id: UUID? = nil) -> Port?
    {
        switch parameter.type
        {
        // A quaternion parameter is also .generic and is left out: its type
        // cannot conform to ParameterValueType, since Satin's decoder traps on it.
        case .generic:
            if let genericParam = parameter as? GenericParameter<Int>        { return makePort(for: genericParam, id: id) }
            if let genericParam = parameter as? GenericParameter<Float>       { return makePort(for: genericParam, id: id) }
            if let genericParam = parameter as? GenericParameter<simd_float3> { return makePort(for: genericParam, id: id) }
            if let genericParam = parameter as? GenericParameter<simd_float4> { return makePort(for: genericParam, id: id) }

        case .string:
            if let genericParam = parameter as? StringParameter { return makePort(for: genericParam, id: id) }

        case .bool:
            if let genericParam = parameter as? BoolParameter { return makePort(for: genericParam, id: id) }

        case .int:
            if let genericParam = parameter as? IntParameter             { return makePort(for: genericParam, id: id) }
            if let genericParam = parameter as? GenericParameter<Int>    { return makePort(for: genericParam, id: id) }

        case .float:
            if let genericParam = parameter as? FloatParameter           { return makePort(for: genericParam, id: id) }
            if let genericParam = parameter as? GenericParameter<Float>  { return makePort(for: genericParam, id: id) }

        case .float2:
            if let genericParam = parameter as? Float2Parameter { return makePort(for: genericParam, id: id) }

        case .float3:
            if let genericParam = parameter as? Float3Parameter { return makePort(for: genericParam, id: id) }

        case .float4:
            if let genericParam = parameter as? Float4Parameter              { return makePort(for: genericParam, id: id) }
            if let genericParam = parameter as? GenericParameter<simd_float4> { return makePort(for: genericParam, id: id) }

        case .float4x4:
            if let genericParam = parameter as? Float4x4Parameter { return makePort(for: genericParam, id: id) }

        default:
            return nil
        }

        return nil
    }

    /// The parameter port sharing `parameter`. Only a value type that can be
    /// one gets here: a plain port would share nothing with the parameter, so
    /// edits to it would change nothing, and `port(for:)` gives nil instead.
    private static func makePort<Value: ParameterValueType & Codable & Hashable>(for parameter: GenericParameter<Value>, id: UUID?) -> Port
    {
        if let id { return ParameterPort(parameter: parameter, id: id) }
        return ParameterPort(parameter: parameter)
    }
}

extension NodePort
{
    /// A port of `Value`'s type as `PortType.makeFreshPort(name:kind:description:id:)`
    /// makes it, a parameter port where the type can carry one, typed for a
    /// node that holds it in a stored property.
    public static func makeFresh(name: String, kind: PortKind, description: String = "") -> NodePort<Value>
    {
        // The factory makes a NodePort<Value>, or a subclass of one, for every
        // PortValueRepresentable type; anything else is a programming error.
        Value.portType.makeFreshPort(name: name, kind: kind, description: description) as! NodePort<Value>
    }
}
