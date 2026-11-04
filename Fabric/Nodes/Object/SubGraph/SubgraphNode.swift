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

    /// The sub graph's published ports, as this node's proxies for them, in
    /// publishing order, ahead of the node's own ports. A proxy is keyed by
    /// the address it stands for in the sub graph, so an inner port retyped
    /// or remade under its key is a retyped proxy: same address, wires moved
    /// where they fit.
    override open func declaredPorts() -> [PortDeclaration]
    {
        self.proxyDeclarations() + super.declaredPorts()
    }

    private func proxyDeclarations() -> [PortDeclaration]
    {
        self.subGraph.getPublishedPorts().compactMap { innerPort in
            guard let innerNode = innerPort.node,
                  let makeProxy = Self.proxyFactory(for: innerPort)
            else { return nil }

            return PortDeclaration(key: .proxy(node: innerNode.id, inner: innerPort.key),
                                   kind: innerPort.kind,
                                   portType: innerPort.portType,
                                   name: innerPort.name,
                                   description: innerPort.portDescription,
                                   control: innerPort.control,
                                   stillDescribes: { ($0 as? any ProxyPortProtocol)?.wraps(innerPort) == true },
                                   makePort: { _ in makeProxy() })
        }
    }

    /// The outlet proxies, which execute forwards from the sub graph.
    private var outletProxies: [any ProxyPortProtocol] = []
    private var hasInletProxies = false

    override open func bindPorts()
    {
        super.bindPorts()
        let proxies = self.ports.filter { $0 is any ProxyPortProtocol }
        self.outletProxies = proxies.filter { $0.kind == .Outlet }.compactMap { $0 as? any ProxyPortProtocol }
        self.hasInletProxies = proxies.contains { $0.kind == .Inlet }
    }

    /// Makes a proxy of the inner port's generic type; nil for a type no
    /// proxy is made for.
    private static func proxyFactory(for port: Port) -> (() -> Port)?
    {
        switch port
        {
        case let p as NodePort<Float>:                              return { ProxyPort(wrapping: p) }
        case let p as NodePort<Int>:                                return { ProxyPort(wrapping: p) }
        case let p as NodePort<Bool>:                               return { ProxyPort(wrapping: p) }
        case let p as NodePort<String>:                             return { ProxyPort(wrapping: p) }
        case let p as NodePort<simd_float2>:                        return { ProxyPort(wrapping: p) }
        case let p as NodePort<simd_float3>:                        return { ProxyPort(wrapping: p) }
        case let p as NodePort<simd_float4>:                        return { ProxyPort(wrapping: p) }
        case let p as NodePort<FabricImage>:                        return { ProxyPort(wrapping: p) }
        case let p as NodePort<Geometry>:                           return { ProxyPort(wrapping: p) }
        case let p as NodePort<Material>:                           return { ProxyPort(wrapping: p) }
        case let p as NodePort<PortValue>:                          return { ProxyPort(wrapping: p) }
        case let p as NodePort<simd_quatf>:                         return { ProxyPort(wrapping: p) }
        case let p as NodePort<simd_float4x4>:                      return { ProxyPort(wrapping: p) }
        case let p as NodePort<ContiguousArray<Float>>:             return { ProxyPort(wrapping: p) }
        case let p as NodePort<ContiguousArray<Int>>:               return { ProxyPort(wrapping: p) }
        case let p as NodePort<ContiguousArray<Bool>>:              return { ProxyPort(wrapping: p) }
        case let p as NodePort<ContiguousArray<String>>:            return { ProxyPort(wrapping: p) }
        case let p as NodePort<ContiguousArray<simd_float2>>:       return { ProxyPort(wrapping: p) }
        case let p as NodePort<ContiguousArray<simd_float3>>:       return { ProxyPort(wrapping: p) }
        case let p as NodePort<ContiguousArray<simd_float4>>:       return { ProxyPort(wrapping: p) }
        case let p as NodePort<ContiguousArray<simd_float4x4>>:     return { ProxyPort(wrapping: p) }
        case let p as NodePort<ContiguousArray<simd_quatf>>:        return { ProxyPort(wrapping: p) }
        case let p as NodePort<ContiguousArray<Geometry>>:          return { ProxyPort(wrapping: p) }
        case let p as NodePort<ContiguousArray<Material>>:          return { ProxyPort(wrapping: p) }
        case let p as NodePort<ContiguousArray<FabricImage>>:       return { ProxyPort(wrapping: p) }
        case let p as NodePort<ContiguousArray<PortValue>>:         return { ProxyPort(wrapping: p) }
        case let p as NodePort<Dictionary<String, Float>>:          return { ProxyPort(wrapping: p) }
        case let p as NodePort<Dictionary<String, Int>>:            return { ProxyPort(wrapping: p) }
        case let p as NodePort<Dictionary<String, Bool>>:           return { ProxyPort(wrapping: p) }
        case let p as NodePort<Dictionary<String, String>>:         return { ProxyPort(wrapping: p) }
        case let p as NodePort<Dictionary<String, simd_float2>>:    return { ProxyPort(wrapping: p) }
        case let p as NodePort<Dictionary<String, simd_float3>>:    return { ProxyPort(wrapping: p) }
        case let p as NodePort<Dictionary<String, simd_float4>>:    return { ProxyPort(wrapping: p) }
        case let p as NodePort<Dictionary<String, simd_float4x4>>:  return { ProxyPort(wrapping: p) }
        case let p as NodePort<Dictionary<String, simd_quatf>>:     return { ProxyPort(wrapping: p) }
        case let p as NodePort<Dictionary<String, Geometry>>:       return { ProxyPort(wrapping: p) }
        case let p as NodePort<Dictionary<String, Material>>:       return { ProxyPort(wrapping: p) }
        case let p as NodePort<Dictionary<String, FabricImage>>:    return { ProxyPort(wrapping: p) }
        case let p as NodePort<Dictionary<String, ContiguousArray<Float>>>:         return { ProxyPort(wrapping: p) }
        case let p as NodePort<Dictionary<String, ContiguousArray<Int>>>:           return { ProxyPort(wrapping: p) }
        case let p as NodePort<Dictionary<String, ContiguousArray<Bool>>>:          return { ProxyPort(wrapping: p) }
        case let p as NodePort<Dictionary<String, ContiguousArray<String>>>:        return { ProxyPort(wrapping: p) }
        case let p as NodePort<Dictionary<String, ContiguousArray<simd_float2>>>:   return { ProxyPort(wrapping: p) }
        case let p as NodePort<Dictionary<String, ContiguousArray<simd_float3>>>:   return { ProxyPort(wrapping: p) }
        case let p as NodePort<Dictionary<String, ContiguousArray<simd_float4>>>:   return { ProxyPort(wrapping: p) }
        case let p as NodePort<Dictionary<String, ContiguousArray<simd_float4x4>>>: return { ProxyPort(wrapping: p) }
        case let p as NodePort<Dictionary<String, ContiguousArray<simd_quatf>>>:    return { ProxyPort(wrapping: p) }
        case let p as NodePort<Dictionary<String, ContiguousArray<Geometry>>>:      return { ProxyPort(wrapping: p) }
        case let p as NodePort<Dictionary<String, ContiguousArray<Material>>>:      return { ProxyPort(wrapping: p) }
        case let p as NodePort<Dictionary<String, ContiguousArray<FabricImage>>>:   return { ProxyPort(wrapping: p) }
        case let p as NodePort<Dictionary<String, PortValue>>:       return { ProxyPort(wrapping: p) }
        default:
            print("ProxyPort: unsupported port type for \(port.name): \(type(of: port))")
            return nil
        }
    }

    override open var nodeExecutionMode:ExecutionMode
    {
        let hasOutletProxies = !self.outletProxies.isEmpty

        // If we have no inputs or outputs, assume we have shit to 'render'
        if !self.hasInletProxies && !hasOutletProxies
        {
            return .Consumer
        }
        
        // if we have no inputs, but have an output we provide
        if !self.hasInletProxies && hasOutletProxies
        {
            return .Provider
        }
        
        // if we have inputs, and outputs we process
        if self.hasInletProxies && hasOutletProxies
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
        self.reconcilePorts()
    }

    /// Wrap an existing graph as this node's sub graph, for embedders that
    /// decode a graph separately and then nest it.
    public init(context: Context, subGraph: Graph)
    {
        self.subGraph = subGraph

        super.init(context: context)
        self.wireSubGraphCallback()
        self.reconcilePorts()
    }

    enum CodingKeys : String, CodingKey
    {
        case subGraph
    }
    
    /// A subgraph node saves only its inner graph: its proxies follow from what
    /// that graph publishes.
    open override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.subGraph, forKey: .subGraph)
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.subGraph = try container.decode(Graph.self, forKey: .subGraph)

        try super.init(from: decoder)
        self.wireSubGraphCallback()
        self.reconcilePorts()
    }

    private func wireSubGraphCallback()
    {
        self.subGraph.onPublishedPortsChanged = { [weak self] in
            self?.reconcilePorts()
        }

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
        for proxy in self.outletProxies
        {
            proxy.forwardFromInner(force:force)
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
