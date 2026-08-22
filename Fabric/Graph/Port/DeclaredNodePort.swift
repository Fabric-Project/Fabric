//
//  DeclaredNodePort.swift
//  Fabric
//

import Foundation

/// Stores values as `Value` while reporting an explicit PortType.
///
/// This is used for recursive container types where Swift cannot construct an
/// arbitrary concrete generic port at runtime, but Fabric still needs to
/// preserve the declared port contract through serialization and publishing.
public final class DeclaredNodePort<Value: PortValueRepresentable>: NodePort<Value>
{
    private let declaredPortType: PortType

    @ObservationIgnored override public var portType: PortType { declaredPortType }

    public init(declaredPortType: PortType,
                name: String,
                kind: PortKind,
                description: String = "",
                id: UUID = UUID())
    {
        self.declaredPortType = declaredPortType
        super.init(name: name, kind: kind, description: description, id: id)
    }

    private enum CodingKeys: String, CodingKey
    {
        case declaredPortType
    }

    required public init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.declaredPortType = try container.decodeIfPresent(PortType.self, forKey: .declaredPortType) ?? Value.portType
        try super.init(from: decoder)
    }

    override public func encode(to encoder: any Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.declaredPortType, forKey: .declaredPortType)
        try super.encode(to: encoder)
    }
}
