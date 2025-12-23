//
//  PortValue.swift
//  Fabric
//
//  Created by Anton Marini on 12/22/25.
//

// A Protocol which defines value types a port can send.
// These types
public protocol PortValueRepresentable : Equatable
{
    static var portType: PortType { get }
}

// Do we actuallt need NSNull?
//extension NSNull : PortValue {
//    
//}

extension Swift.Bool : PortValueRepresentable
{
    public static var portType: PortType { .Bool }

}
extension Swift.Float : PortValueRepresentable
{
    public static var portType: PortType { .Float }
}

extension Swift.Int : PortValueRepresentable
{
    public static var portType: PortType { .Int }

}
extension Swift.String : PortValueRepresentable
{
    public static var portType: PortType { .String }
}

extension simd.simd_float2 : PortValueRepresentable
{
    public static var portType: PortType { .Vector2 }
}

extension simd.simd_float3 : PortValueRepresentable
{
    public static var portType: PortType { .Vector3 }
}

extension simd.simd_float4 : PortValueRepresentable
{
    public static var portType: PortType { .Vector4 }
}

// Temporarily enable these - would need work elsewhere
extension simd.simd_quatf : PortValueRepresentable
{
    public static var portType: PortType { .Quaternion }
}

extension simd.simd_float4x4 : PortValueRepresentable
{
    public static var portType: PortType { .Transform }
}

extension Satin.Geometry : PortValueRepresentable
{
    public static var portType: PortType { .Geometry }
}

extension Satin.Material : PortValueRepresentable
{
    public static var portType: PortType { .Material }
}

extension Satin.Shader : PortValueRepresentable
{
    public static var portType: PortType { .Shader }
}

extension FabricImage : PortValueRepresentable
{
    public static var portType: PortType { .Image }
}

extension ContiguousArray : PortValueRepresentable  where Element : PortValueRepresentable
{
    public static var portType: PortType { .Array(portType: Element.portType) }
}

extension AnyLoggable :  PortValueRepresentable
{
    public static var portType: PortType { .Virtual }
}
