//
//  PortType.swift
//  Fabric
//
//  Created by Anton Marini on 10/20/25.
//

import Foundation
import Satin
import simd

public indirect enum PortType : RawRepresentable, Codable
{
    public typealias RawValue = String
    
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
        case "simd_float2":   self = .Vector2;   return
        case "simd_float3":   self = .Vector3;   return
        case "simd_float4":   self = .Vector4;   return
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
        if s.hasPrefix("Array")
        {
            // Normalize prefixes we’ll accept
            let prefixes = ["Array of "]
                var inner: String?

                for prefix in prefixes
                {
                    if s.hasPrefix(prefix)
                    {
                        let startIdx = s.index(s.startIndex, offsetBy: prefix.count)
                        let endIdx   = s.index(before: s.endIndex) // drop trailing ")"
                        inner = Swift.String(s[startIdx..<endIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                        break
                    }
                }

                if let innerStr = inner, let innerType = PortType(rawValue: innerStr) {
                    self = .Array(portType: innerType)
                    return
                }
            }

            // 3) Unknown
            return nil
    }
    
    public var type:Any.Type {
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
        case .Bool:
             return "Bool"
        case .Float:
            return "Float"
        case .Int:
            return "Int"
        case .String:
            return "String"
        case .Vector2:
            return "simd_float2"
        case .Vector3:
            return "simd_float3"
        case .Vector4:
            return "simd_float4"
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
private func contiguousArrayMetatype<Element>(of _: Element.Type) -> ContiguousArray<Element>.Type {
    ContiguousArray<Element>.self
}

// Implementation that opens the existential and binds `Element`.
@inline(__always)
private func _contiguousArrayMetatype_impl<Element>(_ element: Element.Type) -> Any.Type {
    ContiguousArray<Element>.self
}

// Convenience that accepts Any.Type and returns Any.Type for the array.
@inline(__always)
func contiguousArrayMetatype(of element: Any.Type) -> Any.Type {
    _openExistential(element, do: _contiguousArrayMetatype_impl)
}
