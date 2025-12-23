//
//  PortValue.swift
//  Fabric
//
//  Created by Anton Marini on 12/22/25.
//

// A Protocol which defines value types a port can send.
// These types
public protocol PortValue : Equatable
{
    static var portType: PortType { get }
}

// Do we actuallt need NSNull?
//extension NSNull : PortValue {
//    
//}

extension Swift.Bool : PortValue
{
    public static var portType: PortType { .Bool }

}
extension Swift.Float : PortValue
{
    public static var portType: PortType { .Float }
}

extension Swift.Int : PortValue
{
    public static var portType: PortType { .Int }

}
extension Swift.String : PortValue
{
    public static var portType: PortType { .String }
}

extension simd.simd_float2 : PortValue
{
    public static var portType: PortType { .Vector2 }
}

extension simd.simd_float3 : PortValue
{
    public static var portType: PortType { .Vector3 }
}

extension simd.simd_float4 : PortValue
{
    public static var portType: PortType { .Vector4 }
}

// Temporarily enable these - would need work elsewhere
extension simd.simd_quatf : PortValue
{
    public static var portType: PortType { .Quaternion }
}

extension simd.simd_float4x4 : PortValue
{
    public static var portType: PortType { .Transform }
}

extension Satin.Geometry : PortValue
{
    public static var portType: PortType { .Geometry }
}

extension Satin.Material : PortValue
{
    public static var portType: PortType { .Material }
}

extension Satin.Shader : PortValue
{
    public static var portType: PortType { .Shader }
}

extension FabricImage : PortValue
{
    public static var portType: PortType { .Image }
}

extension ContiguousArray : PortValue  where Element : PortValue
{
    public static var portType: PortType { .Array(portType: Element.portType) }
}

extension AnyLoggable :  PortValue
{
    public static var portType: PortType { .Virtual }
}
