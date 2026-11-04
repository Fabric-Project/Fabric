//
//  PortDeclaration.swift
//  Fabric
//

import Foundation

/// One port of a node's interface, as `Node.declaredPorts()` lists it: the key
/// the registry finds it by and the port.
public struct PortDeclaration
{
    public let key: String
    public let port: Port

    /// A port the node holds in a stored property declares itself under the
    /// key its node finds it by, so the stored reference and the registry name
    /// one object.
    public init(key: String, port: Port)
    {
        self.key = key
        self.port = port
    }
}
