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
    private let declaredPortType: PortType?
    /// Set while this proxy and its inner port copy a value across, so neither echoes it back.
    private var isSyncingWithInnerPort = false

    public var innerPortID: UUID { innerPort.id }

    @ObservationIgnored override public var portType: PortType { declaredPortType ?? super.portType }

    /// Prefers the proxy's own publishedName (set when renamed in the
    /// parent graph), falling back to the inner port's displayName (which
    /// reflects sub-graph level renames).
    override public var displayName: String { publishedName ?? innerPort.displayName }

    public init(
        wrapping innerPort: NodePort<Value>,
        published: Bool = false,
        publishedName: String? = nil
    )
    {
        self.innerPort = innerPort
        self.declaredPortType = innerPort.portType

        // Own UUID, own connections, same kind/name/type as inner port.
        // Published defaults to false — the parent graph independently
        // decides whether to publish this port further.
        super.init(name: innerPort.name,
                   kind: innerPort.kind,
                   description: innerPort.portDescription,
                   id: innerPort.id)
        
        // ensure we proxy other values
        self.parameter = innerPort.parameter
        self.value = innerPort.value
        innerPort.publishingProxy = self
        self.published = published
        self.publishedName = publishedName
    }

    required public init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let innerPortID = try container.decode(UUID.self, forKey: .innerPortID)
        self.declaredPortType = try container.decodeIfPresent(PortType.self, forKey: .declaredPortType)

        guard let decodeContext = decoder.context else {
            fatalError("Required Decode Context Not set")
        }

        // A Subgraph Node will have set the decodeContexts graph
        // to be the actual sub graph
        // this allows us to look up the correct inner port.
        let currentGraph = decodeContext.currentGraph
        let currentGraphNodes = currentGraph?.nodes

        guard let innerPort = currentGraph?.nodePort(forID: innerPortID)
            ?? currentGraphNodes?.flatMap(\.ports).first(where: { $0.id == innerPortID }) else {
            throw ProxyPortBindingError.missingInnerPort(innerPortID)
        }

        guard let typedInnerPort = innerPort as? NodePort<Value> else {
            throw ProxyPortBindingError.typeMismatch(expected: String(describing: Value.self),
                                                     actual: String(describing: type(of: innerPort)))
        }

        self.innerPort = typedInnerPort
        try super.init(from: decoder)
        self.parameter = typedInnerPort.parameter
        self.value = typedInnerPort.value
        typedInnerPort.publishingProxy = self
    }

    private enum CodingKeys: String, CodingKey
    {
        case innerPortID
        case declaredPortType
    }

    override public func encode(to encoder: any Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.innerPortID, forKey: .innerPortID)
        try container.encodeIfPresent(self.declaredPortType, forKey: .declaredPortType)
        try super.encode(to: encoder)
    }

    // MARK: - Value Forwarding

    /// When the parent graph sends a value to this proxy (inlet case),
    /// forward it to the inner port so the sub graph receives it.
    
    /// The parent graph sent a value: forward it to the inner port. The inner port
    /// may resolve it differently (a parameter re-seats nil), so read the result back.
    override internal func valueDidSet()
    {
        if !self.isSyncingWithInnerPort
        {
            self.isSyncingWithInnerPort = true
            self.innerPort.value = self.value
            if self.innerPort.value != self.value { self.value = self.innerPort.value }
            self.isSyncingWithInnerPort = false
        }
        super.valueDidSet()
    }

    /// The inner port changed inside the subgraph: keep this proxy's value the same.
    internal final func mirrorInnerValue(_ innerValue: Value?)
    {
        guard !self.isSyncingWithInnerPort else { return }
        self.isSyncingWithInnerPort = true
        self.value = innerValue
        self.isSyncingWithInnerPort = false
    }

    deinit
    {
        if self.innerPort.publishingProxyIdentifier == ObjectIdentifier(self)
        {
            self.innerPort.publishingProxy = nil
        }
    }
    
    override public var valueDidChange:Bool
    {
        get { innerPort.valueDidChange }
        set {
            innerPort.valueDidChange = newValue
            super.valueDidChange = newValue
        }
    }
    /// Pull the inner port's current value and send it to this proxy's
    /// connections in the parent graph. Called by SubgraphNode after
    /// sub graph execution for outlet proxies.
    public func forwardFromInner(force:Bool = false)
    {
        self.send(innerPort.value, force:force)
    }
}

enum ProxyPortBindingError: Error
{
    case missingInnerPort(UUID)
    case typeMismatch(expected: String, actual: String)
}

extension ProxyPortBindingError: CustomStringConvertible
{
    var description: String
    {
        switch self
        {
        case .missingInnerPort(let id):
            return "Missing inner port for proxy ID \(id)"
        case .typeMismatch(let expected, let actual):
            return "Proxy type mismatch: expected \(expected), got \(actual)"
        }
    }
}
