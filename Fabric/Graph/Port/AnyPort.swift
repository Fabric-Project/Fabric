//
//  AnyPort.swift
//  Fabric
//
//  Created by Anton Marini on 10/19/25.
//

import Foundation
import Satin
import simd

// Type Erased Port wrapper for Serialization

open class AnyPort: Codable {
    public var base: Port

    public init(_ base: Port) {
        self.base = base
    }

    private enum CodingKeys: CodingKey {
        case type
        case base
        case isParameterPort
        case isProxyPort
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let portType = try container.decode(PortType.self, forKey: .type)
        let isParameterPort = try container.decode(Bool.self, forKey: .isParameterPort)
        let isProxyPort = try container.decodeIfPresent(Bool.self, forKey: .isProxyPort) ?? false

        if isProxyPort {
            let portDecoder = try container.superDecoder(forKey: .base)

            switch portType
            {
            case .Bool: self.base = try ProxyPort<Bool>(from: portDecoder)
            case .Float: self.base = try ProxyPort<Float>(from: portDecoder)
            case .Int: self.base = try ProxyPort<Int>(from: portDecoder)
            case .String: self.base = try ProxyPort<String>(from: portDecoder)
            case .Vector2: self.base = try ProxyPort<simd_float2>(from: portDecoder)
            case .Vector3: self.base = try ProxyPort<simd_float3>(from: portDecoder)
            case .Vector4, .Color: self.base = try ProxyPort<simd_float4>(from: portDecoder)
            case .Quaternion: self.base = try ProxyPort<simd_quatf>(from: portDecoder)
            case .Transform: self.base = try ProxyPort<simd_float4x4>(from: portDecoder)
            case .Geometry: self.base = try ProxyPort<Geometry>(from: portDecoder)
            case .Material: self.base = try ProxyPort<Material>(from: portDecoder)
            case .Image: self.base = try ProxyPort<FabricImage>(from: portDecoder)
            case .NumericVirtual: self.base = try NumericVirtualPort(from: portDecoder)
            case .Virtual: self.base = try ProxyPort<PortValue>(from: portDecoder)
            case .Array(portType: let elementType):
                switch elementType {
                case .Bool:             self.base = try ProxyPort<ContiguousArray<Bool>>(from: portDecoder)
                case .Int:              self.base = try ProxyPort<ContiguousArray<Int>>(from: portDecoder)
                case .Float:            self.base = try ProxyPort<ContiguousArray<Float>>(from: portDecoder)
                case .String:           self.base = try ProxyPort<ContiguousArray<String>>(from: portDecoder)
                case .Vector2:          self.base = try ProxyPort<ContiguousArray<simd_float2>>(from: portDecoder)
                case .Vector3:          self.base = try ProxyPort<ContiguousArray<simd_float3>>(from: portDecoder)
                case .Vector4, .Color:  self.base = try ProxyPort<ContiguousArray<simd_float4>>(from: portDecoder)
                case .Quaternion:       self.base = try ProxyPort<ContiguousArray<simd_quatf>>(from: portDecoder)
                case .Transform:        self.base = try ProxyPort<ContiguousArray<simd_float4x4>>(from: portDecoder)
                case .Geometry:         self.base = try ProxyPort<ContiguousArray<Geometry>>(from: portDecoder)
                case .Material:         self.base = try ProxyPort<ContiguousArray<Material>>(from: portDecoder)
                case .Image:            self.base = try ProxyPort<ContiguousArray<FabricImage>>(from: portDecoder)
                default:                self.base = try ProxyPort<ContiguousArray<PortValue>>(from: portDecoder)
                }
            case .Dictionary(valueType: let valueType):
                self.base = try Self.decodeDictionaryProxy(valueType: valueType, from: portDecoder)
            }
        } else {
            let portDecoder = try container.superDecoder(forKey: .base)

            do {
                self.base = try PortType.portForType(portType, isParameterPort: isParameterPort, decoder: portDecoder)!
            }
            catch {
                guard isParameterPort else {
                    throw error
                }

                self.base = try PortType.portForType(portType, isParameterPort: false, decoder: portDecoder)!
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(base.portType, forKey: .type)
        try container.encode((base.parameter == nil) ? false : true, forKey: .isParameterPort)
        try container.encode(base is any ProxyPortProtocol, forKey: .isProxyPort)
        try self.base.encode(to: container.superEncoder(forKey: .base))
    }

    private static func decodeDictionaryProxy(valueType: PortType, from decoder: Decoder) throws -> Port
    {
        switch valueType
        {
        case .Bool:       return try ProxyPort<Dictionary<String, Bool>>(from: decoder)
        case .Int:        return try ProxyPort<Dictionary<String, Int>>(from: decoder)
        case .Float:      return try ProxyPort<Dictionary<String, Float>>(from: decoder)
        case .String:     return try ProxyPort<Dictionary<String, String>>(from: decoder)
        case .Vector2:    return try ProxyPort<Dictionary<String, simd_float2>>(from: decoder)
        case .Vector3:    return try ProxyPort<Dictionary<String, simd_float3>>(from: decoder)
        case .Vector4, .Color:
                          return try ProxyPort<Dictionary<String, simd_float4>>(from: decoder)
        case .Quaternion: return try ProxyPort<Dictionary<String, simd_quatf>>(from: decoder)
        case .Transform:  return try ProxyPort<Dictionary<String, simd_float4x4>>(from: decoder)
        case .Geometry:   return try ProxyPort<Dictionary<String, Geometry>>(from: decoder)
        case .Material:   return try ProxyPort<Dictionary<String, Material>>(from: decoder)
        case .Image:      return try ProxyPort<Dictionary<String, FabricImage>>(from: decoder)
        case .Array(portType: let elementType):
            return try Self.decodeDictionaryOfArrayProxy(elementType: elementType, from: decoder)
        default:
            return try ProxyPort<Dictionary<String, PortValue>>(from: decoder)
        }
    }

    private static func decodeDictionaryOfArrayProxy(elementType: PortType, from decoder: Decoder) throws -> Port
    {
        switch elementType
        {
        case .Bool:       return try ProxyPort<Dictionary<String, ContiguousArray<Bool>>>(from: decoder)
        case .Int:        return try ProxyPort<Dictionary<String, ContiguousArray<Int>>>(from: decoder)
        case .Float:      return try ProxyPort<Dictionary<String, ContiguousArray<Float>>>(from: decoder)
        case .String:     return try ProxyPort<Dictionary<String, ContiguousArray<String>>>(from: decoder)
        case .Vector2:    return try ProxyPort<Dictionary<String, ContiguousArray<simd_float2>>>(from: decoder)
        case .Vector3:    return try ProxyPort<Dictionary<String, ContiguousArray<simd_float3>>>(from: decoder)
        case .Vector4, .Color:
                          return try ProxyPort<Dictionary<String, ContiguousArray<simd_float4>>>(from: decoder)
        case .Quaternion: return try ProxyPort<Dictionary<String, ContiguousArray<simd_quatf>>>(from: decoder)
        case .Transform:  return try ProxyPort<Dictionary<String, ContiguousArray<simd_float4x4>>>(from: decoder)
        case .Geometry:   return try ProxyPort<Dictionary<String, ContiguousArray<Geometry>>>(from: decoder)
        case .Material:   return try ProxyPort<Dictionary<String, ContiguousArray<Material>>>(from: decoder)
        case .Image:      return try ProxyPort<Dictionary<String, ContiguousArray<FabricImage>>>(from: decoder)
        default:          return try ProxyPort<Dictionary<String, PortValue>>(from: decoder)
        }
    }
}
