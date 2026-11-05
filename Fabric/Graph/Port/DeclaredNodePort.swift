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

    override public var portType: PortType { declaredPortType }

    public init(declaredPortType: PortType,
                name: String,
                kind: PortKind,
                description: String = "",
                id: UUID = UUID())
    {
        self.declaredPortType = declaredPortType
        super.init(name: name, kind: kind, description: description, id: id)
    }



}
