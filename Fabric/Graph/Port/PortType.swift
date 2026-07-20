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
    case Transform // (simd_float4x4)
    case Geometry
    case Material
    case Image
    case Array(portType:PortType)
    case Dictionary(valueType:PortType)

    // A Virtual type that boxes all typed values into PortValue
    case Virtual
    // A Virtual type that only allows numeric parameter type connections
    case NumericVirtual
    
    // Leaf and commonly-used nested types for UI menus and serialization dispatch.
    // Does NOT enumerate all possible recursive combinations — use PortType(rawValue:) for dynamic reconstruction.
    public static let allCases : [PortType] = [
        // Numerical
        .Bool,
        .Float,
        .Int,
        .Vector2,
        .Vector3,
        .Vector4,
        .Color,
        .Quaternion,
        .Transform,
        
        // 
        .String,

        // Reference
        .Geometry,
        .Material,
        .Image,
        
        // Collections
        .Array(portType:.Virtual),
        
        .Array(portType:.Bool),
        .Array(portType:.Float),
        .Array(portType:.Int),
        .Array(portType:.String),
        .Array(portType:.Vector2),
        .Array(portType:.Vector3),
        .Array(portType:.Vector4),
        .Array(portType:.Color),
        .Array(portType:.Quaternion),
        .Array(portType:.Transform),
        .Array(portType:.Geometry),
        .Array(portType:.Material),
        .Array(portType:.Image),
        
        .Array(portType:.Dictionary(valueType: .Virtual)),

        
        .Dictionary(valueType:.Virtual),
        
        .Dictionary(valueType:.Bool),
        .Dictionary(valueType:.Float),
        .Dictionary(valueType:.Int),
        .Dictionary(valueType:.String),
        .Dictionary(valueType:.Vector2),
        .Dictionary(valueType:.Vector3),
        .Dictionary(valueType:.Vector4),
        .Dictionary(valueType:.Color),
        .Dictionary(valueType:.Quaternion),
        .Dictionary(valueType:.Transform),
        .Dictionary(valueType:.Geometry),
        .Dictionary(valueType:.Material),
        .Dictionary(valueType:.Image),
       
        .Dictionary(valueType:.Array(portType:.Virtual)),

        // We intentionally skip 'NumericVirtual' as its a bit of an internal implementation detail
        // Since this is used for UI.
        .Virtual
    ]

    /// User-facing leaf value types. Collection nodes use these when the
    /// strategy represents an element type rather than a full port shape.
    public static let scalarCases: [PortType] = [
        .Bool,
        .Float,
        .Int,
        .Vector2,
        .Vector3,
        .Vector4,
        .Color,
        .Quaternion,
        .Transform,
        .String,
        .Geometry,
        .Material,
        .Image,
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
        case "Image":         self = .Image;     return
        case "Numeric Virtual": self = .NumericVirtual; return
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
                        inner = Swift.String(s[startIdx..<endIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
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

        if s.hasPrefix("Dictionary of")
        {
            let prefix = "Dictionary of"
            let startIdx = s.index(s.startIndex, offsetBy: prefix.count)
            let inner = Swift.String(s[startIdx..<s.endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)

            if let valueType = PortType(rawValue: inner)
            {
                self = .Dictionary(valueType: valueType)
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
            return Satin.Geometry.self
        case .Material:
            return Satin.Material.self
        case .Image:
            return FabricImage.self
            
        case .Array(portType: let portType):
            return contiguousArrayMetatype(of: portType.type)
        case .Dictionary(valueType: let valueType):
            return dictionaryMetatype(valueType: valueType.type)
            
        case .NumericVirtual:
            return PortValue.self
        case .Virtual:
            return PortValue.self
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
        case .Image:
            return "Image"
        case .Array(portType: let type):
            return "Array of \(type.rawValue)"
        case .Dictionary(valueType: let type):
            return "Dictionary of \(type.rawValue)"
        case .NumericVirtual:
            return "Numeric Virtual"
        case .Virtual:
            return "Virtual"
        }
    }
}

// MARK: - Parameter Node Mapping

extension PortType {

    public func previewString(for value: PortValue, indent: Swift.String = "") -> Swift.String
    {
        var remainingCharacterCount = Self.maxPreviewCharacterCount

        return Self.previewString(for: value,
                                  indent: indent,
                                  remainingCharacterCount: &remainingCharacterCount)
    }

    private static let maxPreviewCharacterCount = 100

    private static func previewString(for value: PortValue,
                                      indent: Swift.String,
                                      remainingCharacterCount: inout Int) -> Swift.String
    {
        switch value
        {
        case .Bool(let value):
            return Self.capped(Swift.String(value), remainingCharacterCount: &remainingCharacterCount)

        case .Int(let value):
            return Self.capped(Swift.String(value), remainingCharacterCount: &remainingCharacterCount)

        case .Float(let value):
            return Self.capped(Swift.String(value), remainingCharacterCount: &remainingCharacterCount)

        case .String(let value):
            return Self.capped(value, remainingCharacterCount: &remainingCharacterCount)

        case .Vector2(let value):
            return Self.capped(Swift.String(describing: value), remainingCharacterCount: &remainingCharacterCount)

        case .Vector3(let value):
            return Self.capped(Swift.String(describing: value), remainingCharacterCount: &remainingCharacterCount)

        case .Vector4(let value):
            return Self.capped(Swift.String(describing: value), remainingCharacterCount: &remainingCharacterCount)

        case .Quaternion(let value):
            return Self.capped(Swift.String(describing: value), remainingCharacterCount: &remainingCharacterCount)

        case .Transform(let value):
            return Self.listString(
                for: [
                    .Vector4(value.columns.0),
                    .Vector4(value.columns.1),
                    .Vector4(value.columns.2),
                    .Vector4(value.columns.3),
                ],
                indent: indent,
                remainingCharacterCount: &remainingCharacterCount
            )

        case .Geometry(let value):
            return Self.capped(Swift.String(describing: value), remainingCharacterCount: &remainingCharacterCount)

        case .Material(let value):
            return Self.capped(Swift.String(describing: value), remainingCharacterCount: &remainingCharacterCount)

        case .Image(let value):
            return Self.capped(Swift.String(describing: value), remainingCharacterCount: &remainingCharacterCount)

        case .Array(let values):
            return Self.listString(for: values,
                                   indent: indent,
                                   remainingCharacterCount: &remainingCharacterCount)

        case .Dictionary(let values):
            return Self.dictionaryString(for: values,
                                         indent: indent,
                                         remainingCharacterCount: &remainingCharacterCount)
        }
    }

    private static func listString(for values: ContiguousArray<PortValue>,
                                   indent: Swift.String,
                                   remainingCharacterCount: inout Int) -> Swift.String
    {
        let header = Self.capped("Count: \(values.count) ",
                                 remainingCharacterCount: &remainingCharacterCount)

        if values.isEmpty { return header + "[]" }

        let nextIndent = indent + "    "
        var lines: [Swift.String] = []
        var index = values.startIndex

        while index < values.endIndex, remainingCharacterCount > 0
        {
            let renderedValue = Self.previewString(for: values[index],
                                                   indent: nextIndent,
                                                   remainingCharacterCount: &remainingCharacterCount)
            lines.append("\(nextIndent)\(renderedValue),")
            index = values.index(after: index)
        }

        if index < values.endIndex || remainingCharacterCount <= 0
        {
            lines.append("\(nextIndent)...")
        }

        return header + "[\n" + lines.joined(separator: "\n") + "\n\(indent)]"
    }

    private static func dictionaryString(for values: Swift.Dictionary<Swift.String, PortValue>,
                                         indent: Swift.String,
                                         remainingCharacterCount: inout Int) -> Swift.String
    {
        let header = Self.capped("Count: \(values.count) ",
                                 remainingCharacterCount: &remainingCharacterCount)

        if values.isEmpty { return header + "[:]" }

        let nextIndent = indent + "    "
        var lines: [Swift.String] = []
        let sortedKeys = values.keys.sorted()
        var index = sortedKeys.startIndex

        while index < sortedKeys.endIndex, remainingCharacterCount > 0
        {
            let key = sortedKeys[index]
            guard let value = values[key] else
            {
                index = sortedKeys.index(after: index)
                continue
            }

            let renderedKey = Self.capped(key, remainingCharacterCount: &remainingCharacterCount)
            let renderedValue = Self.previewString(for: value,
                                                   indent: nextIndent,
                                                   remainingCharacterCount: &remainingCharacterCount)
            lines.append("\(nextIndent)\(renderedKey): \(renderedValue),")
            index = sortedKeys.index(after: index)
        }

        if index < sortedKeys.endIndex || remainingCharacterCount <= 0
        {
            lines.append("\(nextIndent)...")
        }

        return header + "[\n" + lines.joined(separator: "\n") + "\n\(indent)]"
    }

    private static func capped(_ value: Swift.String,
                               remainingCharacterCount: inout Int) -> Swift.String
    {
        let truncationMarker = "..."

        guard remainingCharacterCount > 0 else { return truncationMarker }

        if value.count <= remainingCharacterCount
        {
            remainingCharacterCount -= value.count
            return value
        }

        let prefixCount = max(0, remainingCharacterCount - truncationMarker.count)
        remainingCharacterCount = 0

        return Swift.String(value.prefix(prefixCount)) + truncationMarker
    }

    /// Returns the parameter node class for this port type,
    /// or nil if no matching parameter node exists.
    public var parameterNodeClass: Node.Type?
    {
        switch self
        {
        case .Float:        return PassThroughNode<Float>.self
        case .Int:          return PassThroughNode<Int>.self
        case .Bool:         return PassThroughNode<Bool>.self
        case .String:       return PassThroughNode<String>.self
        case .Vector2:      return PassThroughNode<simd_float2>.self
        case .Vector3:      return PassThroughNode<simd_float3>.self
        case .Vector4:      return PassThroughNode<simd_float4>.self
        case .Color:        return ColorPassThroughNode.self
        case .Quaternion:   return PassThroughNode<simd_quatf>.self
        case .Transform:    return PassThroughNode<simd_float4x4>.self
        case .Geometry:     return PassThroughNode<Geometry>.self
        case .Material:     return PassThroughNode<Material>.self
        case .Image:        return PassThroughNode<FabricImage>.self
        case .Array(portType: let elementType):
            return Self.arrayParameterNodeClass(for: elementType)
        case .Dictionary(valueType: let valueType):
            return Self.dictionaryParameterNodeClass(for: valueType)
        case .NumericVirtual:
            return nil
        default:
            return nil
        }
    }

    /// Maps a leaf element type to the PassThroughNode class for ContiguousArray<Element>.
    /// Any non-leaf element type (i.e. a nested Array or unknown type) falls back to
    /// ContiguousArray<PortValue> boxing, which handles arbitrary nesting depth.
    private static func arrayParameterNodeClass(for elementType: PortType) -> Node.Type?
    {
        switch elementType
        {
        case .Bool:      return PassThroughNode<ContiguousArray<Bool>>.self
        case .Int:       return PassThroughNode<ContiguousArray<Int>>.self
        case .Float:     return PassThroughNode<ContiguousArray<Float>>.self
        case .String:    return PassThroughNode<ContiguousArray<String>>.self
        case .Vector2:   return PassThroughNode<ContiguousArray<simd_float2>>.self
        case .Vector3:   return PassThroughNode<ContiguousArray<simd_float3>>.self
        case .Vector4, .Color:
                         return PassThroughNode<ContiguousArray<simd_float4>>.self
        case .Quaternion: return PassThroughNode<ContiguousArray<simd_quatf>>.self
        case .Transform: return PassThroughNode<ContiguousArray<simd_float4x4>>.self
        case .Geometry:  return PassThroughNode<ContiguousArray<Geometry>>.self
        case .Material:  return PassThroughNode<ContiguousArray<Material>>.self
        case .Image:     return PassThroughNode<ContiguousArray<FabricImage>>.self
        default:         return PassThroughNode<ContiguousArray<PortValue>>.self
        }
    }

    private static func dictionaryParameterNodeClass(for valueType: PortType) -> Node.Type?
    {
        switch valueType
        {
        case .Bool:      return PassThroughNode<Dictionary<String, Bool>>.self
        case .Int:       return PassThroughNode<Dictionary<String, Int>>.self
        case .Float:     return PassThroughNode<Dictionary<String, Float>>.self
        case .String:    return PassThroughNode<Dictionary<String, String>>.self
        case .Vector2:   return PassThroughNode<Dictionary<String, simd_float2>>.self
        case .Vector3:   return PassThroughNode<Dictionary<String, simd_float3>>.self
        case .Vector4, .Color:
                         return PassThroughNode<Dictionary<String, simd_float4>>.self
        case .Quaternion: return PassThroughNode<Dictionary<String, simd_quatf>>.self
        case .Transform: return PassThroughNode<Dictionary<String, simd_float4x4>>.self
        case .Geometry:  return PassThroughNode<Dictionary<String, Geometry>>.self
        case .Material:  return PassThroughNode<Dictionary<String, Material>>.self
        case .Image:     return PassThroughNode<Dictionary<String, FabricImage>>.self
        default:         return PassThroughNode<Dictionary<String, PortValue>>.self
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

@inline(__always)
fileprivate func dictionaryMetatype<Value>(valueType _: Value.Type) -> Dictionary<String, Value>.Type {
    Dictionary<String, Value>.self
}

@inline(__always)
fileprivate func _dictionaryMetatype_impl<Value>(_ value: Value.Type) -> Any.Type {
    Dictionary<String, Value>.self
}

@inline(__always)
fileprivate func dictionaryMetatype(valueType: Any.Type) -> Any.Type {
    _openExistential(valueType, do: _dictionaryMetatype_impl)
}
