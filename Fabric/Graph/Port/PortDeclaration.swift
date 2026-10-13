//
//  PortDeclaration.swift
//  Fabric
//

import Foundation

/// One port of a node's interface, as `Node.declaredPorts()` lists it: the
/// registry key the port is found by, what kind and type it is, and how to make
/// it. The registry keeps a live port whose key, kind and type match, makes one
/// where the key is missing or the type changed, and retires one no declaration
/// names.
public struct PortDeclaration
{
    public let registryKey: String
    public let kind: PortKind
    public let portType: PortType
    /// The name the made port displays.
    public let name: String
    public let description: String
    /// Whether the made port carries a parameter, where the declaration knows:
    /// a kept port must agree, as a plain port cannot stand for a parameter.
    public let isParameterPort: Bool?

    /// Makes the port. A replacement is made under the id of the port it
    /// replaces, so its wires and proxies follow it; a new port is made under
    /// nil, a fresh id. The registry gives the port the id either way, so a
    /// factory that cannot take one may ignore it.
    public let makePort: (_ id: UUID?) -> Port

    public init(registryKey: String,
                kind: PortKind,
                portType: PortType,
                name: String,
                description: String = "",
                isParameterPort: Bool? = nil,
                makePort: @escaping (_ id: UUID?) -> Port)
    {
        self.registryKey = registryKey
        self.kind = kind
        self.portType = portType
        self.name = name
        self.description = description
        self.isParameterPort = isParameterPort
        self.makePort = makePort
    }

    /// A port of `portType` as `PortType.makeFreshPort` makes it: a parameter
    /// port where the type has a parameter, a plain port otherwise.
    public init(registryKey: String,
                portType: PortType,
                kind: PortKind,
                name: String,
                description: String = "")
    {
        self.init(registryKey: registryKey, kind: kind, portType: portType, name: name, description: description)
        { id in
            portType.makeFreshPort(name: name, kind: kind, description: description, id: id ?? UUID())
        }
    }

    /// A port already made, as `registerPorts(context:)` gives them. The
    /// declaration is used once: declarations are made afresh on each call to
    /// `declaredPorts()`.
    public init(registryKey: String, port: Port)
    {
        self.init(registryKey: registryKey,
                  kind: port.kind,
                  portType: port.portType,
                  name: port.name,
                  description: port.portDescription,
                  isParameterPort: port.parameter != nil,
                  makePort: { _ in port })
    }
}
