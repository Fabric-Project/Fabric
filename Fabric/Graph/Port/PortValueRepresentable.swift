//
//  PortValue.swift
//  Fabric
//
//  Created by Anton Marini on 12/22/25.
//

import simd
import Satin

// A Protocol which defines value types a port can send.
// These types
public protocol PortValueRepresentable : Equatable
{
    static var defaultValue: Self? { get }
    static var portType: PortType { get }
    var portType: PortType { get }
    
    func toPortValue() -> PortValue
    static func fromPortValue(_ value: PortValue) -> Self?
    
    func canConvertTo(other:PortType) -> Bool
    func convertTo(other:PortType) -> (any PortValueRepresentable)?
}

// This is a "boxed" value we use in our cache, and for our new virtual type

public indirect enum PortValue : PortValueRepresentable
{
    case Bool(Bool)
    case Int(Int)
    case Float(Float)
    case String(String)
    case Vector2(simd_float2)
    case Vector3(simd_float3)
    case Vector4(simd_float4)
    case Quaternion(simd_quatf)
    case Transform(simd_float4x4)
    case Geometry(Satin.SatinGeometry)
    case Material(Satin.Material)
    case Shader(Satin.Shader)
    case Image(FabricImage)
    case Virtual(PortValue)

    case Array(ContiguousArray<PortValue>)
    
    public static var defaultValue: PortValue? { nil }
        
    public static var portType: PortType { .Virtual }
    
    public var portType: PortType { .Virtual }
    
    public func toPortValue() -> PortValue {
        return self
    }
    
    public static func fromPortValue(_ value: PortValue) -> PortValue? {
        return value
    }
    
    public func canConvertTo(other:PortType) -> Bool
    {
        switch self
        {
        case .Bool, .Int, .Float, .String:
            switch other
            {
            case .Bool, .Int, .Float, .String:
                return true

            default:
                return false
            }
            
        default:
            return false
        }
        
    }
    
    public func convertTo(other:PortType) -> (any PortValueRepresentable)?
    {
        switch self
        {
        case .Bool(let v):
            return v.convertTo(other: portType)
        
        case .Int(let v):
            return v.convertTo(other: portType)

            case .Float(let v):
            return v.convertTo(other: portType)
            
        case .String(let v):
            return v.convertTo(other: portType)
            
        default:
            return nil
        }
    }
}


extension Swift.Bool : PortValueRepresentable
{
    public static var defaultValue: Bool? { false }
    public static var portType: PortType { .Bool }
    public var portType: PortType { .Bool }

    public func toPortValue() -> PortValue
    {
        .Bool(self)
    }
    
    public static func fromPortValue(_ value: PortValue) ->  Swift.Bool?
    {
        switch value
        {
        case let .Bool(v):
            return v
        default:
            return nil
        }
    }
    
    public func canConvertTo(other:PortType) -> Bool
    {
        switch other
        {
        case .Bool:
            return true
            
        case .Int:
            return true
            
        case .Float:
            return true
            
        case .String:
            return true
            
        default:
            return false
        }
    }
    
    public func convertTo(other:PortType) -> (any PortValueRepresentable)?
    {
        switch other
        {
        case .Bool:
            return self
            
        case .Int:
            return self ? 1 : 0
            
        case .Float:
            return self ? Float(1.0) : Float(0.0)

        case .String:
            return self ? "true" : "false"
        default:
            return nil
        }
    }
}

extension Swift.Int : PortValueRepresentable
{
    public static var defaultValue: Int? { 0 }
    public static var portType: PortType { .Int }
    public var portType: PortType { .Int }

    public func toPortValue() -> PortValue
    {
        .Int(self)
    }
    
    public static func fromPortValue(_ value: PortValue) ->  Swift.Int?
    {
        switch value
        {
        case let .Int(v):
            return v
        default:
            return nil
        }
    }
    
    public func canConvertTo(other:PortType) -> Bool
    {
        switch other
        {
        case .Bool:
            return true
            
        case .Int:
            return true
            
        case .Float:
            return true
            
        case .String:
            return true
            
        default:
            return false
        }
    }
    
    public func convertTo(other:PortType) -> (any PortValueRepresentable)?
    {
        switch other
        {
        case .Bool:
            return self > 0 ? true : false
            
        case .Int:
            return self
            
        case .Float:
            return Float(self)

        case .String:
            return String(self)
        default:
            return nil
        }
    }
}

extension Swift.Float : PortValueRepresentable
{
    public static var defaultValue: Float? { 0.0 }
    public static var portType: PortType { .Float }
    public var portType: PortType { .Float }

    public func toPortValue() -> PortValue
    {
        .Float(self)
    }
    
    public static func fromPortValue(_ value: PortValue) ->  Swift.Float?
    {
        switch value
        {
        case let .Float(v):
            return v
        default:
            return nil
        }
    }
    
    public func canConvertTo(other:PortType) -> Bool
    {
        switch other
        {
        case .Bool:
            return true
            
        case .Int:
            return true
            
        case .Float:
            return true
            
        case .String:
            return true
            
        default:
            return false
        }
    }
    
    public func convertTo(other:PortType) -> (any PortValueRepresentable)?
    {
        switch other
        {
        case .Bool:
            return self > 0.0 ? true : false
            
        case .Int:
            return Int(self)
            
        case .Float:
            return self

        case .String:
            return String(self)
        default:
            return nil
        }
    }
}

extension Swift.String : PortValueRepresentable
{
    public static var defaultValue: String? { "" }
    public static var portType: PortType { .String }
    public var portType: PortType { .String }

    public func toPortValue() -> PortValue
    {
        .String(self)
    }
    
    public static func fromPortValue(_ value: PortValue) ->  Swift.String?
    {
        switch value
        {
        case let .String(v):
            return v
        default:
            return nil
        }
    }
    
    public func canConvertTo(other:PortType) -> Bool
    {
        switch other
        {
        case .Bool:
            return true
            
        case .Int:
            return true
            
        case .Float:
            return true
            
        case .String:
            return true
            
        default:
            return false
        }
    }
    
    public func convertTo(other:PortType) -> (any PortValueRepresentable)?
    {
        switch other
        {
        case .Bool:
            return self.count > 0 ? true : false
            
        case .Int:
            return self.count > 0 ? 1 : 0
            
        case .Float:
            return self.count > 0 ? Float(1.0) : Float(0.0)

        case .String:
            return self
        default:
            return nil
        }
    }
}

extension simd.simd_float2 : PortValueRepresentable
{
    public static var defaultValue: simd_float2? { .zero }
    public static var portType: PortType { .Vector2 }
    public var portType: PortType { .Vector2 }

    public func toPortValue() -> PortValue
    {
        .Vector2(self)
    }
    
    public static func fromPortValue(_ value: PortValue) ->  simd.simd_float2?
    {
        switch value
        {
        case let .Vector2(v):
            return v
        default:
            return nil
        }
    }
    
    public func canConvertTo(other:PortType) -> Bool
    {
        return false
    }
    
    public func convertTo(other:PortType) -> (any PortValueRepresentable)?
    {
        return nil
    }
}

extension simd.simd_float3 : PortValueRepresentable
{
    public static var defaultValue: simd_float3? { .zero }
    public static var portType: PortType { .Vector3 }
    public var portType: PortType { .Vector3 }

    public func toPortValue() -> PortValue
    {
        .Vector3(self)
    }
    
    public static func fromPortValue(_ value: PortValue) ->  simd.simd_float3?
    {
        switch value
        {
        case let .Vector3(v):
            return v
        default:
            return nil
        }
    }
    
    public func canConvertTo(other:PortType) -> Bool
    {
        return false
    }
    
    public func convertTo(other:PortType) -> (any PortValueRepresentable)?
    {
        return nil
    }
}

extension simd.simd_float4 : PortValueRepresentable
{
    public static var defaultValue: simd_float4? { .zero }
    public static var portType: PortType { .Vector4 }
    public var portType: PortType { .Vector4 }

    public func toPortValue() -> PortValue
    {
        .Vector4(self)
    }
    
    public static func fromPortValue(_ value: PortValue) ->  simd.simd_float4?
    {
        switch value
        {
        case let .Vector4(v):
            return v
        default:
            return nil
        }
    }
    
    public func canConvertTo(other:PortType) -> Bool
    {
        return false
    }
    
    public func convertTo(other:PortType) -> (any PortValueRepresentable)?
    {
        return nil
    }
}

// Temporarily enable these - would need work elsewhere
extension simd.simd_quatf : PortValueRepresentable
{
    public static var defaultValue: simd_quatf? { .init(angle: 0, axis: .zero) }
    public static var portType: PortType { .Quaternion }
    public var portType: PortType { .Quaternion }

    public func toPortValue() -> PortValue
    {
        .Quaternion(self)
    }
    
    public static func fromPortValue(_ value: PortValue) ->  simd.simd_quatf?
    {
        switch value
        {
        case let .Quaternion(v):
            return v
        default:
            return nil
        }
    }
    
    public func canConvertTo(other:PortType) -> Bool
    {
        return false
    }
    
    public func convertTo(other:PortType) -> (any PortValueRepresentable)?
    {
        return nil
    }
}

extension simd.simd_float4x4 : PortValueRepresentable
{
    public static var defaultValue: simd_float4x4? { matrix_identity_float4x4 }
    public static var portType: PortType { .Transform }
    public var portType: PortType { .Transform }

    public func toPortValue() -> PortValue
    {
        .Transform(self)
    }
    
    public static func fromPortValue(_ value: PortValue) ->  simd.simd_float4x4?
    {
        switch value
        {
        case let .Transform(v):
            return v
        default:
            return nil
        }
    }
    
    public func canConvertTo(other:PortType) -> Bool
    {
        return false
    }
    
    public func convertTo(other:PortType) -> (any PortValueRepresentable)?
    {
        return nil
    }
}

extension Satin.SatinGeometry : PortValueRepresentable
{
    public static var defaultValue: Self? { nil }
    public static var portType: PortType { .Geometry }
    public var portType: PortType { .Geometry }

    public func toPortValue() -> PortValue
    {
        .Geometry(self)
    }
    
    public static func fromPortValue(_ value: PortValue) ->  Self?
    {
        switch value
        {
        case let .Geometry(v):
            return v as? Self
        default:
            return nil
        }
    }
    
    public func canConvertTo(other:PortType) -> Bool
    {
        return false
    }
    
    public func convertTo(other:PortType) -> (any PortValueRepresentable)?
    {
        return nil
    }
}

extension Satin.Material : PortValueRepresentable
{
    public static var defaultValue: Self? { nil }
    public static var portType: PortType { .Material }
    public var portType: PortType { .Material }

    public func toPortValue() -> PortValue
    {
        .Material(self)
    }
    
    public static func fromPortValue(_ value: PortValue) ->  Self?
    {
        switch value
        {
        case let .Material(v):
            return v as? Self
        default:
            return nil
        }
    }
    
    public func canConvertTo(other:PortType) -> Bool
    {
        return false
    }
    
    public func convertTo(other:PortType) -> (any PortValueRepresentable)?
    {
        return nil
    }
}

extension Satin.Shader : PortValueRepresentable
{
    public static var defaultValue: Self? { nil }
    public static var portType: PortType { .Shader }
    public var portType: PortType { .Shader }

    public func toPortValue() -> PortValue
    {
        .Shader(self)
    }
    
    public static func fromPortValue(_ value: PortValue) ->  Self?
    {
        switch value
        {
        case let .Shader(v):
            return v as? Self
        default:
            return nil
        }
    }
    
    public func canConvertTo(other:PortType) -> Bool
    {
        return false
    }
    
    public func convertTo(other:PortType) -> (any PortValueRepresentable)?
    {
        return nil
    }
}

extension FabricImage : PortValueRepresentable
{
    public static var defaultValue: FabricImage? { nil }
    public static var portType: PortType { .Image }
    public var portType: PortType { .Image }

    public func toPortValue() -> PortValue
    {
        .Image(self)
    }
    
    public static func fromPortValue(_ value: PortValue) ->  FabricImage?
    {
        switch value
        {
        case let .Image(v):
            return v
        default:
            return nil
        }
    }
    
    public func canConvertTo(other:PortType) -> Bool
    {
        return false
    }
    
    public func convertTo(other:PortType) -> (any PortValueRepresentable)?
    {
        return nil
    }
}

extension ContiguousArray: PortValueRepresentable where Element: PortValueRepresentable {

    public static var defaultValue: ContiguousArray<Element>? {  ContiguousArray<Element>() }
    public static var portType: PortType {
        .Array(portType: Element.portType)
    }

    public var portType: PortType {
        .Array(portType: Element.portType)
    }

    
    public func toPortValue() -> PortValue {
        let array:[PortValue] = self.map({$0.toPortValue()} )
        let boxed: ContiguousArray<PortValue> = ContiguousArray<PortValue>( array )
        return .Array(boxed)
    }

    public static func fromPortValue(_ value: PortValue) -> ContiguousArray<Element>? {
        switch value {
        case let .Array(v):
            var result = ContiguousArray<Element>()
            result.reserveCapacity(v.count)

            for boxedElement in v {
                guard let element = Element.fromPortValue(boxedElement) else { return nil }
                result.append(element)
            }

            return result

        default:
            return nil
        }
    }
    
    public func canConvertTo(other:PortType) -> Bool
    {
        return false
    }
    
    public func convertTo(other:PortType) -> (any PortValueRepresentable)?
    {
        return nil
    }
}
