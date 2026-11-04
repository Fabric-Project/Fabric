//
//  SubgraphNode.swift
//  Fabric
//
//  Created by Anton Marini on 6/22/25.
//

import Foundation
import Satin
import simd
import Metal

open class SubgraphNode: BaseObjectNode
{
    override open class var name:String { "Sub Graph" }
    override open class var nodeType:Node.NodeType { Node.NodeType.Subgraph }
    override open class var nodeExecutionMode: Node.ExecutionMode { .Consumer } // TODO: ??
    override open class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override open class var nodeDescription: String { "A Sub Graph of Nodes, useful for organizing or encapsulation"}

    public private(set) var subGraph:Graph

    /// The proxies standing for the sub graph's published ports, one per
    /// port, as ports of this node in the graph around. Made as the node is
    /// built (see reconcileProxies()); after that, changed only as the sub
    /// graph tells this node of each change to its published set.
    private var proxyPorts: [Port] = []

    override open var ports:[Port] { self.proxyPorts + super.ports }

    private func proxy(over port: Port) -> Port?
    {
        self.proxyPorts.first { $0.id == port.id }
    }

    /// `ports` have joined the sub graph's published set.
    internal func innerPortsDidPublish(_ ports: [Port])
    {
        let proxies = ports.filter { self.proxy(over: $0) == nil }.compactMap { self.makeOwnProxy(over: $0) }
        guard !proxies.isEmpty else { return }

        self.proxyPorts.append(contentsOf: proxies)
        self.proxiesDidChange()
    }

    /// `ports` are about to leave the sub graph's published set. Their proxies
    /// lose their wires and leave the published set of the graph around, which
    /// tells its own sub graph node in turn, before they go.
    internal func innerPortsWillUnpublish(_ ports: [Port])
    {
        let proxies = ports.compactMap { self.proxy(over: $0) }
        guard !proxies.isEmpty else { return }

        self.graph?.disconnectAndUnpublish(proxies, of: self)

        self.proxyPorts.removeAll { proxy in proxies.contains { $0 === proxy } }
        proxies.forEach { $0.node = nil }
        self.proxiesDidChange()
    }

    /// `new` has replaced `old` in the sub graph's published set under the
    /// same id. A proxy of the same value type and name forwards to `new` in
    /// place; otherwise the proxy is made again under the same id, published
    /// as it was. Either way the graph around keeps the wires the proxy can
    /// still take.
    internal func innerPort(_ old: Port, wasReplacedBy new: Port)
    {
        guard let proxy = self.proxy(over: old) else
        {
            self.innerPortsDidPublish([new])
            return
        }

        if let retargeted = proxy as? any ProxyPortProtocol, retargeted.retarget(to: new)
        {
            self.graph?.rebindWires(from: proxy, to: proxy)
            self.proxiesDidChange()
            // The proxy above this one forwards to it, and takes its new parameter.
            if proxy.published { self.graph?.port(proxy, wasReplacedBy: proxy) }
            return
        }

        guard let index = self.proxyPorts.firstIndex(where: { $0 === proxy }),
              let remade = self.remakeProxy(over: new, carrying: proxy)
        else
        {
            self.innerPortsWillUnpublish([old])
            return
        }

        // Assigned before the rebind, so the topology recalculation sees the
        // remade proxy; the wires still reference the old one.
        self.proxyPorts[index] = remade
        self.graph?.rebindWires(from: proxy, to: remade)
        proxy.node = nil
        self.proxiesDidChange()
        if remade.published { self.graph?.port(proxy, wasReplacedBy: remade) }
    }

    /// A proxy of this node over `port`, published as `proxy` is. `proxy`
    /// stood over the port `port` replaced. Nil where `port`'s type has no
    /// proxy.
    private func remakeProxy(over port: Port, carrying proxy: Port) -> Port?
    {
        guard let remade = self.makeOwnProxy(over: port) else { return nil }
        remade.setPublishing(proxy.published, name: proxy.publishedName)
        return remade
    }

    /// A proxy over `port`, as a port of this node; nil where `port`'s type
    /// has no proxy.
    private func makeOwnProxy(over port: Port) -> Port?
    {
        guard let proxy = Self.makeProxy(for: port) else { return nil }
        proxy.node = self
        return proxy
    }

    /// `new`, published in the sub graph, takes over from `old`, which is
    /// about to be unpublished: the wires on `old`'s proxy move to `new`'s
    /// proxy, as does its publishing in the graph around.
    internal func innerPort(_ old: Port, handsOverTo new: Port)
    {
        guard let graph = self.graph,
              let oldProxy = self.proxy(over: old),
              let newProxy = self.proxy(over: new)
        else { return }

        graph.transferWires(from: oldProxy, to: newProxy)
        graph.transferPublishing(from: oldProxy, to: newProxy)
    }

    /// `port`, published in the sub graph, has a new published name, which
    /// its proxy shows unless it has one of its own.
    internal func innerPortDidRename(_ port: Port)
    {
        guard let proxy = self.proxy(over: port) else { return }

        self.proxiesDidChange()
        if proxy.published { self.graph?.portDidRename(proxy) }
    }

    /// Brings the proxies to the sub graph's published set, once, as the node
    /// is built. A decoded proxy is kept where it forwards to the published
    /// port under its id, made again where that port was replaced, and dropped
    /// where none is published; a published port with no proxy gets one.
    private func reconcileProxies()
    {
        let innerPorts = self.subGraph.getPublishedPorts()
        let innerPortsByID = Dictionary(innerPorts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var proxies: [Port] = []
        for proxy in self.proxyPorts
        {
            if let innerPort = innerPortsByID[proxy.id],
               let typed = proxy as? any ProxyPortProtocol
            {
                if typed.wraps(innerPort)
                {
                    proxy.node = self
                    proxies.append(proxy)
                    continue
                }
                if let remade = self.remakeProxy(over: innerPort, carrying: proxy)
                {
                    proxies.append(remade)
                }
            }
            // Decoding set node on every proxy. A discarded proxy can outlive
            // this node in views, so it must not keep the unowned reference.
            proxy.node = nil
        }

        for innerPort in innerPorts where !proxies.contains(where: { $0.id == innerPort.id })
        {
            if let proxy = self.makeOwnProxy(over: innerPort)
            {
                proxies.append(proxy)
            }
        }

        self.proxyPorts = proxies
        self.proxiesDidChange()
    }

    private func proxiesDidChange()
    {
        self.invalidatePortCaches()

        self.parameterGroup.clear()
        for port in self.ports
        {
            if let param = port.parameter
            {
                self.parameterGroup.append(param)
            }
        }
        self.synchronizeParameters()

        self.graph?.markConnectionsChanged()
        self.portsChangedSubject.send()
    }

    /// Type-erase proxy creation — matches the inner port's generic type.
    private static func makeProxy(for port: Port) -> Port?
    {
        switch port
        {
        case let p as NodePort<Float>:                              return ProxyPort(wrapping: p)
        case let p as NodePort<Int>:                                return ProxyPort(wrapping: p)
        case let p as NodePort<Bool>:                               return ProxyPort(wrapping: p)
        case let p as NodePort<String>:                             return ProxyPort(wrapping: p)
        case let p as NodePort<simd_float2>:                        return ProxyPort(wrapping: p)
        case let p as NodePort<simd_float3>:                        return ProxyPort(wrapping: p)
        case let p as NodePort<simd_float4>:                        return ProxyPort(wrapping: p)
        case let p as NodePort<FabricImage>:                        return ProxyPort(wrapping: p)
        case let p as NodePort<Geometry>:                           return ProxyPort(wrapping: p)
        case let p as NodePort<Material>:                           return ProxyPort(wrapping: p)
        case let p as NodePort<PortValue>:                          return ProxyPort(wrapping: p)
        case let p as NodePort<simd_quatf>:                         return ProxyPort(wrapping: p)
        case let p as NodePort<simd_float4x4>:                      return ProxyPort(wrapping: p)
        case let p as NodePort<ContiguousArray<Float>>:             return ProxyPort(wrapping: p)
        case let p as NodePort<ContiguousArray<Int>>:               return ProxyPort(wrapping: p)
        case let p as NodePort<ContiguousArray<Bool>>:              return ProxyPort(wrapping: p)
        case let p as NodePort<ContiguousArray<String>>:            return ProxyPort(wrapping: p)
        case let p as NodePort<ContiguousArray<simd_float2>>:       return ProxyPort(wrapping: p)
        case let p as NodePort<ContiguousArray<simd_float3>>:       return ProxyPort(wrapping: p)
        case let p as NodePort<ContiguousArray<simd_float4>>:       return ProxyPort(wrapping: p)
        case let p as NodePort<ContiguousArray<simd_float4x4>>:     return ProxyPort(wrapping: p)
        case let p as NodePort<ContiguousArray<simd_quatf>>:        return ProxyPort(wrapping: p)
        case let p as NodePort<ContiguousArray<Geometry>>:          return ProxyPort(wrapping: p)
        case let p as NodePort<ContiguousArray<Material>>:          return ProxyPort(wrapping: p)
        case let p as NodePort<ContiguousArray<FabricImage>>:       return ProxyPort(wrapping: p)
        case let p as NodePort<ContiguousArray<PortValue>>:         return ProxyPort(wrapping: p)
        case let p as NodePort<Dictionary<String, Float>>:          return ProxyPort(wrapping: p)
        case let p as NodePort<Dictionary<String, Int>>:            return ProxyPort(wrapping: p)
        case let p as NodePort<Dictionary<String, Bool>>:           return ProxyPort(wrapping: p)
        case let p as NodePort<Dictionary<String, String>>:         return ProxyPort(wrapping: p)
        case let p as NodePort<Dictionary<String, simd_float2>>:    return ProxyPort(wrapping: p)
        case let p as NodePort<Dictionary<String, simd_float3>>:    return ProxyPort(wrapping: p)
        case let p as NodePort<Dictionary<String, simd_float4>>:    return ProxyPort(wrapping: p)
        case let p as NodePort<Dictionary<String, simd_float4x4>>:  return ProxyPort(wrapping: p)
        case let p as NodePort<Dictionary<String, simd_quatf>>:     return ProxyPort(wrapping: p)
        case let p as NodePort<Dictionary<String, Geometry>>:       return ProxyPort(wrapping: p)
        case let p as NodePort<Dictionary<String, Material>>:       return ProxyPort(wrapping: p)
        case let p as NodePort<Dictionary<String, FabricImage>>:    return ProxyPort(wrapping: p)
        case let p as NodePort<Dictionary<String, ContiguousArray<Float>>>:         return ProxyPort(wrapping: p)
        case let p as NodePort<Dictionary<String, ContiguousArray<Int>>>:           return ProxyPort(wrapping: p)
        case let p as NodePort<Dictionary<String, ContiguousArray<Bool>>>:          return ProxyPort(wrapping: p)
        case let p as NodePort<Dictionary<String, ContiguousArray<String>>>:        return ProxyPort(wrapping: p)
        case let p as NodePort<Dictionary<String, ContiguousArray<simd_float2>>>:   return ProxyPort(wrapping: p)
        case let p as NodePort<Dictionary<String, ContiguousArray<simd_float3>>>:   return ProxyPort(wrapping: p)
        case let p as NodePort<Dictionary<String, ContiguousArray<simd_float4>>>:   return ProxyPort(wrapping: p)
        case let p as NodePort<Dictionary<String, ContiguousArray<simd_float4x4>>>: return ProxyPort(wrapping: p)
        case let p as NodePort<Dictionary<String, ContiguousArray<simd_quatf>>>:    return ProxyPort(wrapping: p)
        case let p as NodePort<Dictionary<String, ContiguousArray<Geometry>>>:      return ProxyPort(wrapping: p)
        case let p as NodePort<Dictionary<String, ContiguousArray<Material>>>:      return ProxyPort(wrapping: p)
        case let p as NodePort<Dictionary<String, ContiguousArray<FabricImage>>>:   return ProxyPort(wrapping: p)
        case let p as NodePort<Dictionary<String, PortValue>>:       return ProxyPort(wrapping: p)
        default:
            print("ProxyPort: unsupported port type for \(port.name): \(type(of: port))")
            return nil
        }
    }

    override open var nodeExecutionMode:ExecutionMode
    {
        let publishedInputPorts = self.proxyPorts.filter { $0.kind == .Inlet }
        let publishedOutputPorts = self.proxyPorts.filter { $0.kind == .Outlet }

        // If we have no inputs or outputs, assume we have shit to 'render'
        if publishedInputPorts.isEmpty && publishedOutputPorts.isEmpty
        {
            return .Consumer
        }
        
        // if we have no inputs, but have an output we provide
        if publishedInputPorts.isEmpty && !publishedOutputPorts.isEmpty
        {
            return .Provider
        }
        
        // if we have inputs, and outputs we process
        if !publishedInputPorts.isEmpty && !publishedOutputPorts.isEmpty
        {
            return .Processor
        }

        // Safety ?
        return Self.nodeExecutionMode
    }

    override open func getObject() -> Object?
    {
        return self.object
    }

    open var object:Object? {
        self.subGraph.scene
    }
    
    public required init(context: Context)
    {
        self.subGraph = Graph(context: context)

        super.init(context: context)
        self.wireSubGraphCallback()
        self.reconcileProxies()
    }

    /// Wrap an existing graph as this node's sub graph, for embedders that
    /// decode a graph separately and then nest it.
    public init(context: Context, subGraph: Graph)
    {
        self.subGraph = subGraph

        super.init(context: context)
        self.wireSubGraphCallback()
        self.reconcileProxies()
    }

    enum CodingKeys : String, CodingKey
    {
        case subGraph
        case proxyPorts
    }
    
    open override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.subGraph, forKey: .subGraph)
        try container.encode(self.proxyPorts.map(AnyPort.init), forKey: .proxyPorts)
        
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.subGraph = try container.decode(Graph.self, forKey: .subGraph)
        
        // We set the current graph to the subgraph
        // to allow proxy ports and any other decode contexts to work correctly
        
        if let decodeContext = decoder.context
        {
            let previousGraph = decodeContext.currentGraph

            decodeContext.currentGraph = self.subGraph

            defer
            {
                decodeContext.currentGraph = previousGraph
            }

            self.proxyPorts = Self.decodeProxyPortsIfPossible(from: container, forKey: .proxyPorts)
        }
        else
        {
            self.proxyPorts = Self.decodeProxyPortsIfPossible(from: container, forKey: .proxyPorts)
        }

        try super.init(from: decoder)
        self.wireSubGraphCallback()
        self.reconcileProxies()
    }

    private static func decodeProxyPortsIfPossible(from container: KeyedDecodingContainer<CodingKeys>,
                                                   forKey key: CodingKeys) -> [Port]
    {
        do
        {
            return try container.decodeIfPresent([AnyPort].self, forKey: key)?.map(\.base) ?? []
        }
        catch
        {
            print("Failed to decode saved subgraph proxy ports: \(error)")
            return []
        }
    }

    private func wireSubGraphCallback()
    {
        self.subGraph.ownerNode = self

        self.subGraph.onCameraSelectionChanged = { [weak self] in
            guard let self, !(self is DeferredSubgraphNode) else { return }
            self.graph?.updateCameraSelection()
        }
    }
     
    // Ensure we always render!
//    override public var isDirty:Bool { get {  true /*self.subGraph.needsExecution*/  } set { } }
    override open var isDirty:Bool { get {  self.subGraph.needsExecution  } set { } }


    override open func markClean()
    {
        for node in self.subGraph.nodes where node.hasPendingExecutionCleanup
        {
            node.markClean()
        }
        
        super.markClean()
    }
         
    override open func markDirty()
    {
        for node in self.subGraph.nodes
        {
            node.markDirty()
        }
        
        super.markDirty()
    }
    
    /// Ordinary subgraphs run on their parent's renderer; a deferred subgraph owns one.
    internal var childGraphRenderer: GraphRenderer? { nil }

    /// Iterator evaluates every inner node, connected or not.
    internal var startsAllChildNodes: Bool { false }

    override open func startExecution(renderer:GraphRenderer) throws
    {
        self.transitionSubgraph(to: .started, renderer: renderer)
        try super.startExecution(renderer: renderer)
    }

    override open func stopExecution(renderer:GraphRenderer) throws
    {
        self.transitionSubgraph(to: .stopped, renderer: renderer)
        try super.stopExecution(renderer: renderer)
    }

    override open func enableExecution(renderer:GraphRenderer) throws
    {
        self.transitionSubgraph(to: .enabled, renderer: renderer)
        try super.enableExecution(renderer: renderer)
    }

    override open func disableExecution(renderer:GraphRenderer) throws
    {
        self.transitionSubgraph(to: .disabled, renderer: renderer)
        try super.disableExecution(renderer: renderer)
    }

    /// An inner node's failure is reported, not thrown: it is that node's
    /// failure, not the subgraph node's, which still reaches its own state.
    private func transitionSubgraph(to state: ExecutionState, renderer: GraphRenderer)
    {
        do
        {
            if let childGraphRenderer = self.childGraphRenderer
            {
                try childGraphRenderer.transitionExecution(to: state)
            }
            else
            {
                try renderer.reconcileAllNodes(in: self.subGraph, ceiling: state, startsAllNodes: self.startsAllChildNodes)
            }
        }
        catch
        {
            renderer.errorDelegate?.renderer(renderer, didFailWith: error)
        }
    }

    open func forwardPortValues(force:Bool = false)
    {
        // Forward outlet values from inner ports to proxy ports so the
        // parent graph receives sub graph outputs.
        for port in self.proxyPorts where port.kind == .Outlet
        {
            (port as? any ProxyPortProtocol)?.forwardFromInner(force:force)
        }
    }
    
    override open func execute(renderer:GraphRenderer,
                                  executionInfo:GraphExecutionInfo,
                                  renderPassDescriptor: MTLRenderPassDescriptor,
                                  commandBuffer: MTLCommandBuffer) throws    {
        
        // The inner pass runs every node it can and rethrows the first failure
        // afterwards, so outlets of the nodes that did run must still reach the
        // parent graph — the parent's markClean cascade clears their flags
        // whether or not this call threw.
        defer { self.forwardPortValues(force:true) }

        try renderer.execute(graph: self.subGraph,
                             executionInfo: executionInfo,
                             renderPassDescriptor: renderPassDescriptor,
                             commandBuffer: commandBuffer,
                             clearFlags: false)
    }
}
