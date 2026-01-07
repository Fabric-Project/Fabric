//
//  PortType.swift
//  Fabric
//
//  Created by Anton Marini on 10/20/25.
//

import Foundation
import Satin
import simd


// PortType conversions and factories to instantiate specialized NodePorts and map Swift value types to canonical PortTypes
// TODO: Ideally this somehow is turned into a recursive thing that builds a port up somehow?
public indirect enum PortType : RawRepresentable, Codable, Equatable, CaseIterable
{
    public typealias RawValue = String
    
    case Bool
    case Int // TODO: Index
    case Float // TODO: Number
    case String
    case Vector2
    case Vector3
    case Vector4
    case Color
    case Quaternion //(simd quatf)
    case Transform // (mid_matrix4x4
    case Geometry
    case Material
    case Shader
    case Image
    case Array(portType:PortType)
    case Virtual
    
    // This is brittle
    public static let allCases : [PortType] = [
        .Bool,
        .Float,
        .Int,
        .String,
        .Vector2,
        .Vector3,
        .Vector4,
        .Color,
        .Quaternion,
        .Transform,
        
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
        .Array(portType:.Image),
        
        .Virtual

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
        case "Quaternion":    self = .Quaternion; return
        case "Transform":     self = .Transform; return
        case "Geometry":      self = .Geometry;  return
        case "Material":      self = .Material;  return
        case "Shader":        self = .Shader;    return
        case "Image":         self = .Image;     return
        case "Virtual":       self = .Virtual;    return
            
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
    
    public var type:Any.Type  {
        switch self {
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
        case .Quaternion:
            return simd.simd_quatf.self
        case .Transform:
            return simd.simd_float4x4.self
        case .Geometry:
            return Satin.SatinGeometry.self
        case .Material:
            return Satin.Material.self
        case .Shader:
            return Satin.Shader.self
        case .Image:
            return FabricImage.self
        case .Array(portType: let portType):
            return contiguousArrayMetatype(of: portType.type)
        case .Virtual:
            return PortType.self
        }
    }
    
    public var rawValue: String {
        switch self {
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
        case .Quaternion:
            return "Quaternion"
        case .Transform:
            return "Transform"
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
        case .Virtual:
            return "Virtual"
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
