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

    /// ProxyPorts wrapping the sub graph's published ports.
    /// Each proxy has node = self (the SubgraphNode) and published = false.
    /// The parent graph independently decides whether to publish them further.
    /// Lazily rebuilt when the sub graph's published ports change.
    private var proxyPorts: [Port] = []

    override open var ports:[Port] { self.proxyPorts + super.ports }

    /// Rebuild proxy ports from the sub graph's current published ports.
    /// Called via callback when the sub graph's published ports change.
    open func rebuildProxyPorts()
    {
        self.invalidatePortCaches()

        let innerPorts = self.subGraph.getPublishedPorts()
        let publishedIDs = Set(innerPorts.map(\.id))

        // Remove proxies whose inner port is no longer published
        self.proxyPorts.removeAll { proxy in
            guard let proxy = proxy as? any ProxyPortProtocol else { return true }
            return !publishedIDs.contains(proxy.innerPortID)
        }

        // Add proxies for newly published ports
        let existingInnerIDs = Set(self.proxyPorts.compactMap { ($0 as? any ProxyPortProtocol)?.innerPortID })
        for innerPort in innerPorts where !existingInnerIDs.contains(innerPort.id)
        {
            if let proxy = Self.makeProxy(for: innerPort)
            {
                proxy.node = self
                self.proxyPorts.append(proxy)
            }
        }
        
        // Ensure parameter group is updated
        self.parameterGroup.clear()

        for port in self.ports
        {
            if let param = port.parameter
            {
                self.parameterGroup.append(param)
            }
        }

        self.synchronizeParameters()

        self.invalidatePortCaches()
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
        self.rebuildProxyPorts()
    }

    /// Wrap an existing graph as this node's sub graph, for embedders that
    /// decode a graph separately and then nest it.
    public init(context: Context, subGraph: Graph)
    {
        self.subGraph = subGraph

        super.init(context: context)
        self.wireSubGraphCallback()
        self.rebuildProxyPorts()
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
        self.proxyPorts.forEach { $0.node = self }
        self.rebuildProxyPorts()
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
        self.subGraph.onPublishedPortsChanged = { [weak self] in
            self?.rebuildProxyPorts()
        }
    }
     
    // Ensure we always render!
//    override public var isDirty:Bool { get {  true /*self.subGraph.needsExecution*/  } set { } }
    override open var isDirty:Bool { get {  self.subGraph.needsExecution  } set { } }


    override open func markClean()
    {
        for node in self.subGraph.nodes
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
    
    override open func startExecution(renderer:GraphRenderer) throws
    {
        try renderer.startExecution(graph: self.subGraph)
    }

    override open func stopExecution(renderer:GraphRenderer) throws
    {
        try renderer.stopExecution(graph: self.subGraph)
    }

    override open func enableExecution(renderer:GraphRenderer) throws
    {
        try renderer.enableExecution(graph: self.subGraph)
    }

    override open func disableExecution(renderer:GraphRenderer) throws
    {
        try renderer.disableExecution(graph: self.subGraph)
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
