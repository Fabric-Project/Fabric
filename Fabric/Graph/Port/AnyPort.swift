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
            case .Geometry: self.base = try ProxyPort<SatinGeometry>(from: portDecoder)
            case .Material: self.base = try ProxyPort<Material>(from: portDecoder)
            case .Shader: self.base = try ProxyPort<Shader>(from: portDecoder)
            case .Image: self.base = try ProxyPort<FabricImage>(from: portDecoder)
            case .Virtual: self.base = try ProxyPort<PortValue>(from: portDecoder)
            case .Array:
                throw DecodingError.dataCorruptedError(forKey: .type,
                                                       in: container,
                                                       debugDescription: "Proxy ports do not yet support array-valued ports")
            }
        } else {
            self.base = try PortType.portForType(portType, isParameterPort: isParameterPort, decoder: container.superDecoder(forKey: .base))!
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(base.portType, forKey: .type)
        try container.encode((base.parameter == nil) ? false : true, forKey: .isParameterPort)
        try container.encode(base is any ProxyPortProtocol, forKey: .isProxyPort)
        try self.base.encode(to: container.superEncoder(forKey: .base))
    }
}
