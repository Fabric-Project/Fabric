//
//  PortType.swift
//  Fabric
//
//  Created by Anton Marini on 10/20/25.
//

import Foundation
import Satin
import simd

// A Protocol which defines value types a port can send.
public protocol FabricPort : Equatable {}

extension NSNull : FabricPort { }

extension Swift.Bool : FabricPort { }
extension Swift.Float : FabricPort { }
extension Swift.Int : FabricPort { }
extension Swift.String : FabricPort { }
extension simd.simd_float2 : FabricPort { }
extension simd.simd_float3 : FabricPort { }
extension simd.simd_float4 : FabricPort { }

// Temporarily enable these - would need work elsewhere 
extension simd.simd_quatf : FabricPort { }
extension simd.simd_float2x2 : FabricPort { }
extension simd.simd_float3x3 : FabricPort { }
extension simd.simd_float4x4 : FabricPort { }

extension Satin.Geometry : FabricPort { }
extension Satin.Material : FabricPort { }
extension Satin.Shader : FabricPort { }
extension EquatableTexture : FabricPort { }

extension ContiguousArray : FabricPort  where Element : FabricPort { }

extension AnyLoggable :  FabricPort { }


// Optional unwrapping for metatypes (why is this my life?) -
fileprivate  protocol _AnyOptional { static var wrapped: Any.Type { get } }
extension Optional: _AnyOptional { fileprivate static var wrapped: Any.Type { Wrapped.self } }
fileprivate  func unwrapOptional(_ t: Any.Type) -> Any.Type {
    (t as? _AnyOptional.Type)?.wrapped ?? t
}

// PortType conversions and factories to instantiate specialized NodePorts and map Swift value types to canonical PortTypes
// TODO: Ideally this somehow is turned into a recursive thing that builds a port up somehow? 
public indirect enum PortType : RawRepresentable, Codable, Equatable, CaseIterable
{
    public typealias RawValue = String
    
    public static func portForType(_ type:PortType, isParameterPort:Bool, decoder:Decoder) throws -> Port?
    {
        switch type
        {
        case .Bool: return try isParameterPort ? ParameterPort<Bool>.init(from: decoder) : NodePort<Bool>.init(from: decoder)
        case .Float: return try isParameterPort ? ParameterPort<Float>.init(from: decoder) : NodePort<Float>.init(from: decoder)
        case .Int: return try isParameterPort ? ParameterPort<Int>.init(from: decoder) : NodePort<Int>.init(from: decoder)
        case .String: return try isParameterPort ? ParameterPort<String>.init(from: decoder) : NodePort<String>.init(from: decoder)
        case .Vector2: return try isParameterPort ?  ParameterPort<simd_float2>.init(from: decoder) : NodePort<simd_float2>.init(from: decoder)
        case .Vector3: return try isParameterPort ?  ParameterPort<simd_float3>.init(from: decoder) : NodePort<simd_float3>.init(from: decoder)
        case .Vector4: return try isParameterPort ?  ParameterPort<simd_float4>.init(from: decoder) : NodePort<simd_float4>.init(from: decoder)
        case .Color: return try isParameterPort ?  ParameterPort<simd_float4>.init(from: decoder) : NodePort<simd_float4>.init(from: decoder)
            
        case .Geometry: return try NodePort<Satin.Geometry>.init(from: decoder)
        case .Material: return try NodePort<Satin.Material>.init(from: decoder)
        case .Shader: return try NodePort<Satin.Shader>.init(from: decoder)
        case .Image: return try NodePort<EquatableTexture>.init(from: decoder)
        // TODO: Array
        case .Array(portType: let arrayType):
            switch arrayType
            {
            case .Bool: return try isParameterPort ? ParameterPort<ContiguousArray<Bool>>.init(from: decoder) : NodePort<ContiguousArray<Bool>>.init(from: decoder)
            case .Float: return try isParameterPort ? ParameterPort<ContiguousArray<Float>>.init(from: decoder) : NodePort<ContiguousArray<Float>>.init(from: decoder)
            case .Int: return try isParameterPort ? ParameterPort<ContiguousArray<Int>>.init(from: decoder) : NodePort<ContiguousArray<Int>>.init(from: decoder)
            case .String: return try isParameterPort ? ParameterPort<ContiguousArray<String>>.init(from: decoder) : NodePort<ContiguousArray<String>>.init(from: decoder)
            case .Vector2: return try isParameterPort ?  ParameterPort<ContiguousArray<simd_float2>>.init(from: decoder) : NodePort<ContiguousArray<simd_float2>>.init(from: decoder)
            case .Vector3: return try isParameterPort ?  ParameterPort<ContiguousArray<simd_float3>>.init(from: decoder) : NodePort<ContiguousArray<simd_float3>>.init(from: decoder)
            case .Vector4: return try isParameterPort ?  ParameterPort<ContiguousArray<simd_float4>>.init(from: decoder) : NodePort<ContiguousArray<simd_float4>>.init(from: decoder)
            case .Color: return try isParameterPort ?  ParameterPort<ContiguousArray<simd_float4>>.init(from: decoder) : NodePort<ContiguousArray<simd_float4>>.init(from: decoder)
                
            case .Geometry: return try NodePort<ContiguousArray<Satin.Geometry>>.init(from: decoder)
            case .Material: return try NodePort<ContiguousArray<Satin.Material>>.init(from: decoder)
            case .Shader: return try NodePort<ContiguousArray<Satin.Shader>>.init(from: decoder)
            case .Image: return try NodePort<ContiguousArray<EquatableTexture>>.init(from: decoder)

            // we dont yet support nested arrays///
            case .Array(portType: _):
                return nil
            }
        }
    }
    
    public static func portForType(from parameter:(any Parameter)) -> Port?
    {
    //        print(self.name, "parameterToPort", parameter.label)
                    
            switch parameter.type
            {
                
            case .generic:
                
                if let genericParam = parameter as? GenericParameter<Float>
                {
                    return ParameterPort(parameter: genericParam)
                }
                
                if let genericParam = parameter as? GenericParameter<simd_float3>
                {
                    return ParameterPort(parameter: genericParam)
                }
                
                if let genericParam = parameter as? GenericParameter<simd_float4>
                {
                    return ParameterPort(parameter: genericParam)
                }
                
                if let genericParam = parameter as? GenericParameter<simd_quatf>
                {
                    return ParameterPort(parameter: genericParam)
                }
                
            case .string:
                
                if let genericParam = parameter as? StringParameter
                {
                    return ParameterPort(parameter: genericParam)
                }

            case .bool:

                if let genericParam = parameter as? BoolParameter
                {
                    return ParameterPort(parameter: genericParam)
                }
                
            case .float:
                
                if let genericParam = parameter as? FloatParameter
                {
                    return ParameterPort(parameter: genericParam)
                }

                else if let genericParam = parameter as? GenericParameter<Float>
                {
                    return ParameterPort(parameter: genericParam)
                }

            case .float2:
                if let genericParam = parameter as? Float2Parameter
                {
                    return ParameterPort(parameter: genericParam)
                }
                
            case .float3:
                if let genericParam = parameter as? Float3Parameter
                {
                    return ParameterPort(parameter: genericParam)
                }
                
            case .float4:
                if let genericParam = parameter as? Float4Parameter
                {
                    return ParameterPort(parameter: genericParam)
                }
                
                else if let genericParam = parameter as? GenericParameter<simd_float4>
                {
                    return ParameterPort(parameter: genericParam)
                }
                
            case .float2x2:
                if let genericParam = parameter as? Float2x2Parameter
                {
                    return ParameterPort(parameter: genericParam)
                }
                
            case .float3x3:
                if let genericParam = parameter as? Float3x3Parameter
                {
                    return ParameterPort(parameter: genericParam)
                }

            case .float4x4:
                if let genericParam = parameter as? Float4x4Parameter
                {
                    return ParameterPort(parameter: genericParam)
                }

            default:
                return nil

            }
            
            return nil
        
    }
//
    
    static func fromType(_ raw:Any.Type) -> PortType
    {
        let type = unwrapOptional(raw.self)

        if type == Swift.Bool.self               { return .Bool }
        else if type == Swift.Float.self         { return .Float }
        else if type == Swift.Int.self           { return .Int }
        else if type == Swift.String.self        { return .String }
        else if type == simd_float2.self         { return .Vector2 }
        else if type == simd_float3.self         { return .Vector3 }
        else if type == simd_float4.self         { return .Vector4 }
        else if type == Satin.Geometry.self      { return .Geometry }
        else if type == Satin.Material.self      { return .Material }
        else if type == Satin.Shader.self        { return .Shader }
        else if type == EquatableTexture.self    { return .Image }

        // Assume Array?
        else {
            if let optionalArrayElementType = contiguousArrayElementType(of: type)
            {
                let arrayElementType = unwrapOptional(optionalArrayElementType)
                return .Array(portType: PortType.fromType(arrayElementType ) )
            }
        }
        
        return .Bool

    }
    
    case Bool
    case Float
    case Int
    case String
    case Vector2
    case Vector3
    case Vector4
    case Color
    // Quaternion (simd_quatf)
    // Transform (simd_float_4x4)
    case Geometry
    case Material
    case Shader
    case Image
    
    case Array(portType:PortType)
    
    public static let allCases : [PortType] = [
        .Bool,
        .Float,
        .Int,
        .String,
        .Vector2,
        .Vector3,
        .Vector4,
        .Color,
        .Geometry,
        .Material,
        .Shader,
        .Image,
        
        .Array(portType:.Bool),
        .Array(portType:.Float),
        .Array(portType:.Int),
        .Array(portType:.String),
        .Array(portType:.Vector2),
        .Array(portType:.Vector3),
        .Array(portType:.Vector4),
        .Array(portType:.Color),
        .Array(portType:.Geometry),
        .Array(portType:.Material),
        .Array(portType:.Shader),
        .Array(portType:.Image)
    ]
    
    public init?(rawValue: String)
    {
        let s = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1) Simple, non-recursive cases
        switch s
        {
        case "Bool":          self = .Bool;      return
        case "Float":         self = .Float;     return
        case "Int":           self = .Int;       return
        case "String":        self = .String;    return
        case "Vector 2":      self = .Vector2;   return
        case "Vector 3":      self = .Vector3;   return
        case "Vector 4":      self = .Vector4;   return
        case "Color":         self = .Color;     return
        case "Geometry":      self = .Geometry;  return
        case "Material":      self = .Material;  return
        case "Shader":        self = .Shader;    return
        case "Image":         self = .Image;     return
        default: break
        }
        
        // 2) Recursive "Array of ..." case (the format produced by `rawValue`)
        //    Accepts minor whitespace variations.
        //    Example: "Array of simd_float2"
        if s.hasPrefix("Array of")
        {
            // Normalize prefixes we’ll accept
            let prefixes = ["Array of"]
                var inner: String?

                for prefix in prefixes
                {
                    if s.hasPrefix(prefix)
                    {
                        let startIdx = s.index(s.startIndex, offsetBy: prefix.count)
                        let endIdx   = s.endIndex
                        inner = Swift.String(s[startIdx..<endIdx]).trimmingCharacters(in: .newlines)
                        break
                    }
                }

                if let innerStr = inner,
                   let innerType = PortType(rawValue: innerStr)
                {
                    self = .Array(portType: innerType)
                    return
                }
            }

        return nil
            // 3) Unknown
//        self =  .Unsupported
//        fatalError("unsupported port type")
    }
    
    public var type:Any.Type {
        switch self {
//        case .Unsupported:
//            return NSNull.self
        case .Bool:
            return Swift.Bool.self
        case .Float:
            return Swift.Float.self
        case .Int:
            return Swift.Int.self
        case .String:
            return Swift.String.self
        case .Vector2:
            return simd.simd_float2.self
        case .Vector3:
            return simd.simd_float3.self
        case .Vector4:
            return simd.simd_float4.self
        case .Color:
            return simd.simd_float4.self // could this backire?
        case .Geometry:
            return Satin.Geometry.self
        case .Material:
            return Satin.Material.self
        case .Shader:
            return Satin.Shader.self
        case .Image:
            return EquatableTexture.self
        case .Array(portType: let portType):
            return contiguousArrayMetatype(of: portType.type)
        }
    }
    
    public var rawValue: String {
        switch self {
//        case .Unsupported:
//            return "Unsupported"
        case .Bool:
             return "Bool"
        case .Float:
            return "Float"
        case .Int:
            return "Int"
        case .String:
            return "String"
        case .Vector2:
            return "Vector 2"
        case .Vector3:
            return "Vector 3"
        case .Vector4:
            return "Vector 4"
        case .Color:
            return "Color" // could this backire?
        case .Geometry:
            return "Geometry"
        case .Material:
            return "Material"
        case .Shader:
            return "Shader"
        case .Image:
            return "Image"
        case .Array(portType: let type):
            return "Array of \(type.rawValue)"
        }
    }
}

// Generic helper that lifts an element metatype to a ContiguousArray metatype.
@inline(__always)
fileprivate func contiguousArrayMetatype<Element>(of _: Element.Type) -> ContiguousArray<Element>.Type {
    ContiguousArray<Element>.self
}

// Implementation that opens the existential and binds `Element`.
@inline(__always)
fileprivate func _contiguousArrayMetatype_impl<Element>(_ element: Element.Type) -> Any.Type {
    ContiguousArray<Element>.self
}

// Convenience that accepts Any.Type and returns Any.Type for the array.
@inline(__always)
fileprivate func contiguousArrayMetatype(of element: Any.Type) -> Any.Type {
    _openExistential(element, do: _contiguousArrayMetatype_impl)
}

// 1) A protocol only the *type* (metatype) needs to conform to.
fileprivate protocol _ContiguousArrayElementProvider {
    static var _elementType: Any.Type { get }
}

// 2) Make ContiguousArray conform and surface `Element.self`.
extension ContiguousArray: _ContiguousArrayElementProvider {
    fileprivate static var _elementType: Any.Type { Element.self }
}

// 3) Given Any.Type that may be a ContiguousArray<T>.Type, return T.Type.
@inline(__always)
func contiguousArrayElementType(of type: Any.Type) -> Any.Type? {
    (type as? _ContiguousArrayElementProvider.Type)?._elementType
}

// (Optional) Convenience for a value instance
@inline(__always)
func contiguousArrayElementType(of value: Any) -> Any.Type? {
    contiguousArrayElementType(of: Swift.type(of: value))
}
