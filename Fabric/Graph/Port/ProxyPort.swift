//
//  ProxyPort.swift
//  Fabric
//
//  Created by Claude on 3/29/26.
//

import Foundation
import Satin

/// Protocol for type-erased access to ProxyPort's inner port identity.
/// Used by SubgraphNode to manage proxy lifecycle without knowing the generic type.
protocol ProxyPortProtocol
{
    var innerPortID: UUID { get }
    func forwardFromInner(force:Bool)
}

/// A port that wraps an inner port from a sub graph, presenting it as
/// a port on the SubgraphNode in the parent graph.
///
/// ProxyPort is the SubgraphNode's abstraction boundary. The parent graph
/// connects to ProxyPorts; the inner ports and their sub graph connections
/// are private implementation details.
///
/// Value forwarding:
/// - **Inlet**: when the parent graph sends a value to the proxy, the
///   value didSet forwards it to the inner port via `send(force: true)`,
///   which propagates to the inner port's sub graph connections.
/// - **Outlet**: after sub graph execution, `SubgraphNode` calls
///   `forwardFromInner()` to pull the inner port's value and send it
///   to the proxy's parent graph connections.
public class ProxyPort<Value: PortValueRepresentable>: NodePort<Value>, ProxyPortProtocol
{
    private let innerPort: NodePort<Value>

    public var innerPortID: UUID { innerPort.id }

    /// Prefers the proxy's own publishedName (set when renamed in the
    /// parent graph), falling back to the inner port's displayName (which
    /// reflects sub-graph level renames).
    override public var displayName: String { publishedName ?? innerPort.displayName }

    public init(wrapping innerPort: NodePort<Value>)
    {
        self.innerPort = innerPort

        // Own UUID, own connections, same kind/name/type as inner port.
        // Published defaults to false — the parent graph independently
        // decides whether to publish this port further.
        super.init(name: innerPort.name, kind: innerPort.kind, description: innerPort.portDescription)
        
        // ensure we proxy other values
        self.parameter = innerPort.parameter
        self.value = innerPort.value
    }

    required public init(from decoder: any Decoder) throws
    {
        fatalError("ProxyPort is not independently decodable — it is reconstructed by SubgraphNode from the sub graph's published ports")
    }

    // MARK: - Value Forwarding

    /// When the parent graph sends a value to this proxy (inlet case),
    /// forward it to the inner port so the sub graph receives it.
    
    override public var value: Value?
    {
        get { innerPort.value }
        set { innerPort.value = newValue }
    }
    
    override public var valueDidChange:Bool
    {
        get { innerPort.valueDidChange }
        set { innerPort.valueDidChange = newValue }
    }
    /// Pull the inner port's current value and send it to this proxy's
    /// connections in the parent graph. Called by SubgraphNode after
    /// sub graph execution for outlet proxies.
    public func forwardFromInner(force:Bool = false)
    {
        self.send(innerPort.value, force:force)
    }
}
