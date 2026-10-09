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
    public static func portForType(_ type: PortType, isParameterPort: Bool, decoder: Decoder) throws -> Port?
    {
        switch type
        {
        case .Bool:       return try isParameterPort ? ParameterPort<Bool>.init(from: decoder)          : NodePort<Bool>.init(from: decoder)
        case .Float:      return try isParameterPort ? ParameterPort<Float>.init(from: decoder)         : NodePort<Float>.init(from: decoder)
        case .Int:        return try isParameterPort ? ParameterPort<Int>.init(from: decoder)           : NodePort<Int>.init(from: decoder)
        case .String:     return try isParameterPort ? ParameterPort<String>.init(from: decoder)        : NodePort<String>.init(from: decoder)
        case .Vector2:    return try isParameterPort ? ParameterPort<simd_float2>.init(from: decoder)   : NodePort<simd_float2>.init(from: decoder)
        case .Vector3:    return try isParameterPort ? ParameterPort<simd_float3>.init(from: decoder)   : NodePort<simd_float3>.init(from: decoder)
        case .Vector4:    return try isParameterPort ? ParameterPort<simd_float4>.init(from: decoder)   : NodePort<simd_float4>.init(from: decoder)
        case .Color:      return try isParameterPort ? ParameterPort<simd_float4>.init(from: decoder)   : ColorNodePort.init(from: decoder)
        case .Quaternion: return try isParameterPort ? ParameterPort<simd_quatf>.init(from: decoder)    : NodePort<simd_quatf>.init(from: decoder)
        case .Transform:  return try isParameterPort ? ParameterPort<simd_float4x4>.init(from: decoder) : NodePort<simd_float4x4>.init(from: decoder)
        case .Geometry:   return try NodePort<Satin.Geometry>.init(from: decoder)
        case .Material:   return try NodePort<Satin.Material>.init(from: decoder)
        case .Image:      return try NodePort<FabricImage>.init(from: decoder)
        case .NumericVirtual: return try NumericVirtualPort.init(from: decoder)
        case .Virtual:    return try NodePort<PortValue>.init(from: decoder)

        case .Array(portType: let elementType):
            return try Self.arrayPort(elementType: elementType, isParameterPort: isParameterPort, decoder: decoder)

        case .Dictionary(valueType: let valueType):
            return try Self.dictionaryPort(dictionaryType: type, valueType: valueType, isParameterPort: isParameterPort, decoder: decoder)
        }
    }

    /// Constructs the concrete port for ContiguousArray<Element> given the element PortType.
    /// Leaf element types produce strongly-typed ports. Any non-leaf element (nested Array or
    /// unknown type) falls back to ContiguousArray<PortValue> boxing, which handles arbitrary
    /// nesting depth without enumerating combinations.
    private static func arrayPort(elementType: PortType, isParameterPort: Bool, decoder: Decoder) throws -> Port
    {
        switch elementType
        {
        case .Bool:
            return try isParameterPort ? ParameterPort<ContiguousArray<Bool>>.init(from: decoder)        : NodePort<ContiguousArray<Bool>>.init(from: decoder)
        case .Int:
            return try isParameterPort ? ParameterPort<ContiguousArray<Int>>.init(from: decoder)         : NodePort<ContiguousArray<Int>>.init(from: decoder)
        case .Float:
            return try isParameterPort ? ParameterPort<ContiguousArray<Float>>.init(from: decoder)       : NodePort<ContiguousArray<Float>>.init(from: decoder)
        case .String:
            return try isParameterPort ? ParameterPort<ContiguousArray<String>>.init(from: decoder)      : NodePort<ContiguousArray<String>>.init(from: decoder)
        case .Vector2:
            return try isParameterPort ? ParameterPort<ContiguousArray<simd_float2>>.init(from: decoder) : NodePort<ContiguousArray<simd_float2>>.init(from: decoder)
        case .Vector3:
            return try isParameterPort ? ParameterPort<ContiguousArray<simd_float3>>.init(from: decoder) : NodePort<ContiguousArray<simd_float3>>.init(from: decoder)
        case .Vector4:
            return try isParameterPort ? ParameterPort<ContiguousArray<simd_float4>>.init(from: decoder) : NodePort<ContiguousArray<simd_float4>>.init(from: decoder)
        case .Color:
            return try isParameterPort ? ParameterPort<ContiguousArray<simd_float4>>.init(from: decoder) : ColorArrayNodePort.init(from: decoder)
        case .Quaternion:
            return try NodePort<ContiguousArray<simd_quatf>>.init(from: decoder)
        case .Transform:
            return try NodePort<ContiguousArray<simd_float4x4>>.init(from: decoder)
        case .Geometry:
            return try NodePort<ContiguousArray<Satin.Geometry>>.init(from: decoder)
        case .Material:
            return try NodePort<ContiguousArray<Satin.Material>>.init(from: decoder)
        case .Image:
            return try NodePort<ContiguousArray<FabricImage>>.init(from: decoder)

        default:
            // Nested arrays (Array of Array of T) and unrecognised element types fall back to
            // PortValue boxing. ContiguousArray<PortValue> round-trips correctly for any structure.
            return try DeclaredNodePort<ContiguousArray<PortValue>>.init(from: decoder)
        }
    }

    private static func dictionaryPort(dictionaryType: PortType, valueType: PortType, isParameterPort: Bool, decoder: Decoder) throws -> Port
    {
        switch valueType
        {
        case .Bool:
            return try NodePort<Dictionary<String, Bool>>.init(from: decoder)
        case .Int:
            return try NodePort<Dictionary<String, Int>>.init(from: decoder)
        case .Float:
            return try NodePort<Dictionary<String, Float>>.init(from: decoder)
        case .String:
            return try NodePort<Dictionary<String, String>>.init(from: decoder)
        case .Vector2:
            return try NodePort<Dictionary<String, simd_float2>>.init(from: decoder)
        case .Vector3:
            return try NodePort<Dictionary<String, simd_float3>>.init(from: decoder)
        case .Vector4:
            return try NodePort<Dictionary<String, simd_float4>>.init(from: decoder)
        case .Color:
            return try DeclaredNodePort<Dictionary<String, simd_float4>>.init(from: decoder)
        case .Quaternion:
            return try NodePort<Dictionary<String, simd_quatf>>.init(from: decoder)
        case .Transform:
            return try NodePort<Dictionary<String, simd_float4x4>>.init(from: decoder)
        case .Geometry:
            return try NodePort<Dictionary<String, Satin.Geometry>>.init(from: decoder)
        case .Material:
            return try NodePort<Dictionary<String, Satin.Material>>.init(from: decoder)
        case .Image:
            return try NodePort<Dictionary<String, FabricImage>>.init(from: decoder)
        case .Array(portType: let elementType):
            return try Self.dictionaryOfArrayPort(dictionaryType: dictionaryType, elementType: elementType, decoder: decoder)
        case .Virtual:
            return try NodePort<Dictionary<String, PortValue>>.init(from: decoder)
        default:
            return try DeclaredNodePort<Dictionary<String, PortValue>>.init(from: decoder)
        }
    }

    private static func dictionaryOfArrayPort(dictionaryType: PortType, elementType: PortType, decoder: Decoder) throws -> Port
    {
        switch elementType
        {
        case .Bool:        return try NodePort<Dictionary<String, ContiguousArray<Bool>>>.init(from: decoder)
        case .Int:         return try NodePort<Dictionary<String, ContiguousArray<Int>>>.init(from: decoder)
        case .Float:       return try NodePort<Dictionary<String, ContiguousArray<Float>>>.init(from: decoder)
        case .String:      return try NodePort<Dictionary<String, ContiguousArray<String>>>.init(from: decoder)
        case .Vector2:     return try NodePort<Dictionary<String, ContiguousArray<simd_float2>>>.init(from: decoder)
        case .Vector3:     return try NodePort<Dictionary<String, ContiguousArray<simd_float3>>>.init(from: decoder)
        case .Vector4:
                            return try NodePort<Dictionary<String, ContiguousArray<simd_float4>>>.init(from: decoder)
        case .Color:
                            return try DeclaredNodePort<Dictionary<String, ContiguousArray<simd_float4>>>.init(from: decoder)
        case .Quaternion:  return try NodePort<Dictionary<String, ContiguousArray<simd_quatf>>>.init(from: decoder)
        case .Transform:   return try NodePort<Dictionary<String, ContiguousArray<simd_float4x4>>>.init(from: decoder)
        case .Geometry:    return try NodePort<Dictionary<String, ContiguousArray<Satin.Geometry>>>.init(from: decoder)
        case .Material:    return try NodePort<Dictionary<String, ContiguousArray<Satin.Material>>>.init(from: decoder)
        case .Image:       return try NodePort<Dictionary<String, ContiguousArray<FabricImage>>>.init(from: decoder)
        default:           return try DeclaredNodePort<Dictionary<String, PortValue>>.init(from: decoder)
        }
    }

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
    /// own when unwired; every other port is plain. For deserialization use
    /// `portForType(_:isParameterPort:decoder:)` instead.
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
