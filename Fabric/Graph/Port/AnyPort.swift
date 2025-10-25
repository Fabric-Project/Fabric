//
//  AnyPort.swift
//  Fabric
//
//  Created by Anton Marini on 10/19/25.
//


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
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let portType = try container.decode(PortType.self, forKey: .type)
        let isParameterPort = try container.decode(Bool.self, forKey: .isParameterPort)
        
        self.base = try PortType.nodeForType(portType, isParameterPort: isParameterPort, decoder: container.superDecoder(forKey: .base))!
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(base.portType, forKey: .type)
        try container.encode((base.parameter == nil) ? false : true, forKey: .isParameterPort)
        try self.base.encode(to: container.superEncoder(forKey: .base))
    }
}
