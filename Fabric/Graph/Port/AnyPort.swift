//
//  AnyPort.swift
//  Fabric
//
//  Created by Anton Marini on 10/19/25.
//




//open class AnyPort: Codable {
//    public var base: Port
//
//    public init(_ base: Port) {
//        self.base = base
//    }
//
//    private enum CodingKeys: CodingKey {
//        case type, base
//    }
//
//    public required init(from decoder: Decoder) throws {
//        let container = try decoder.container(keyedBy: CodingKeys.self)
//        let typeString = try container.decode(String.self, forKey: .type)
//        let type
//        base = try NodePort<type>.init(from: container.superDecoder(forKey: .base))
//    }
//
//    public func encode(to encoder: Encoder) throws {
//        var container = encoder.container(keyedBy: CodingKeys.self)
//        try container.encode(base.type, forKey: .type)
//        try base.encode(to: container.superEncoder(forKey: .base))
//    }
//}
