//
//  PortDeclaration.swift
//  Fabric
//

import Foundation

/// One port of a node's interface, as `Node.declaredPorts()` lists it: the key
/// the registry finds it by, what kind and type it is, how it presents, and how
/// to make it. Code-owned: a declaration is a function of the node's settings
/// and what it reads at runtime, never of the document.
public struct PortDeclaration
{
    public let key: PortKey
    public let kind: PortKind
    public let portType: PortType
    /// The name the made port displays.
    public let name: String
    public let description: String
    /// Non-nil for a parameter inlet. See PortControl.
    public let control: PortControl?

    /// Whether a port already under this key still stands for this
    /// declaration, where its kind, type and control agreeing is not enough:
    /// a proxy must wrap this inner port, not another under the same key. Nil
    /// accepts any. One that does not is replaced as a retyped port is.
    public let stillDescribes: ((Port) -> Bool)?

    /// Makes the port. A retyped port is made under the runtime id of the one
    /// it replaces, so views keyed on it follow; a new port under nil, a fresh
    /// id. The registry gives the port the id either way, so a factory that
    /// cannot take one may ignore it.
    public let makePort: (_ id: UUID?) -> Port

    public init(key: PortKey,
                kind: PortKind,
                portType: PortType,
                name: String,
                description: String = "",
                control: PortControl?,
                stillDescribes: ((Port) -> Bool)? = nil,
                makePort: @escaping (_ id: UUID?) -> Port)
    {
        self.key = key
        self.kind = kind
        self.portType = portType
        self.name = name
        self.description = description
        self.control = control
        self.stillDescribes = stillDescribes
        self.makePort = makePort
    }

    /// A port of `portType` as `PortType.makeFreshPort` makes it: a parameter
    /// port where the type has a parameter, a plain port otherwise.
    public init(key: String,
                portType: PortType,
                kind: PortKind,
                name: String,
                description: String = "")
    {
        self.init(key: .own(key),
                  kind: kind,
                  portType: portType,
                  name: name,
                  description: description,
                  control: portType.freshPortControl(kind: kind))
        { id in
            portType.makeFreshPort(name: name, kind: kind, description: description, id: id ?? UUID())
        }
    }

    /// A port already made: one a node holds in a stored property for typed
    /// access, or one `registerPorts(context:)` made. A node that holds the port
    /// declares that object, so its property and the registry name one port.
    public init(key: String, port: Port)
    {
        self.init(key: .own(key), port: port)
    }

    public init(key: PortKey, port: Port)
    {
        self.init(key: key,
                  kind: port.kind,
                  portType: port.portType,
                  name: port.name,
                  description: port.portDescription,
                  control: port.parameter.map { PortControl($0.controlType) },
                  makePort: { _ in port })
    }
}
