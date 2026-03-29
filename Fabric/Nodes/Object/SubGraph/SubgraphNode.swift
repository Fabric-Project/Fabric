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

public class SubgraphNode: BaseObjectNode
{
    override public class var name:String { "Sub Graph" }
    override public class var nodeType:Node.NodeType { Node.NodeType.Subgraph }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer } // TODO: ??
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "A Sub Graph of Nodes, useful for organizing or encapsulation"}

    let subGraph:Graph

    /// ProxyPorts wrapping the sub graph's published ports.
    /// Each proxy has node = self (the SubgraphNode) and published = false.
    /// The parent graph independently decides whether to publish them further.
    /// Lazily rebuilt when the sub graph's published ports change.
    @ObservationIgnored private var proxyPorts: [Port] = []

    override public var ports:[Port] { self.proxyPorts + super.ports }

    /// Rebuild proxy ports from the sub graph's current published ports.
    /// Called via callback when the sub graph's published ports change.
    public func rebuildProxyPorts()
    {
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
    }

    /// Type-erase proxy creation — matches the inner port's generic type.
    private static func makeProxy(for port: Port) -> Port?
    {
        switch port
        {
        case let p as NodePort<Float>:           return ProxyPort(wrapping: p)
        case let p as NodePort<Int>:             return ProxyPort(wrapping: p)
        case let p as NodePort<Bool>:            return ProxyPort(wrapping: p)
        case let p as NodePort<String>:          return ProxyPort(wrapping: p)
        case let p as NodePort<simd_float2>:     return ProxyPort(wrapping: p)
        case let p as NodePort<simd_float3>:     return ProxyPort(wrapping: p)
        case let p as NodePort<simd_float4>:     return ProxyPort(wrapping: p)
        case let p as NodePort<FabricImage>:     return ProxyPort(wrapping: p)
        case let p as NodePort<SatinGeometry>:   return ProxyPort(wrapping: p)
        case let p as NodePort<Material>:        return ProxyPort(wrapping: p)
        case let p as NodePort<PortValue>:       return ProxyPort(wrapping: p)
        case let p as NodePort<simd_quatf>:      return ProxyPort(wrapping: p)
        case let p as NodePort<simd_float4x4>:   return ProxyPort(wrapping: p)
        default:
            print("ProxyPort: unsupported port type for \(port.name): \(type(of: port))")
            return nil
        }
    }

    @ObservationIgnored override public var nodeExecutionMode:ExecutionMode
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

    override public func getObject() -> Object?
    {
        return self.object
    }
    
    public var object:Object? {
        self.subGraph.scene
    }
    
    public required init(context: Context)
    {
        self.subGraph = Graph(context: context)

        super.init(context: context)
        self.wireSubGraphCallback()
        self.rebuildProxyPorts()
    }
    
    enum CodingKeys : String, CodingKey
    {
        case subGraph
    }
    
    public override func encode(to encoder:Encoder) throws
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
        self.rebuildProxyPorts()
    }

    private func wireSubGraphCallback()
    {
        self.subGraph.onPublishedPortsChanged = { [weak self] in
            self?.rebuildProxyPorts()
        }
    }
     
    // Ensure we always render!
//    override public var isDirty:Bool { get {  true /*self.subGraph.needsExecution*/  } set { } }
    override public var isDirty:Bool { get {  self.subGraph.needsExecution  } set { } }


    override public func markClean()
    {
        for node in self.subGraph.nodes
        {
            node.markClean()
        }
        
        super.markClean()
    }
         
    override public func markDirty()
    {
        for node in self.subGraph.nodes
        {
            node.markDirty()
        }
        
        super.markDirty()
    }
    
    override public func startExecution(context:GraphExecutionContext)
    {
        context.graphRenderer?.startExecution(graph: self.subGraph, executionContext: context)
    }
    
    override public func stopExecution(context:GraphExecutionContext)
    {
        context.graphRenderer?.stopExecution(graph: self.subGraph, executionContext: context)
    }

    override public func enableExecution(context:GraphExecutionContext)
    {
        context.graphRenderer?.enableExecution(graph: self.subGraph, executionContext: context)
    }
    
    override public func disableExecution(context:GraphExecutionContext)
    {
        context.graphRenderer?.disableExecution(graph: self.subGraph, executionContext: context)
    }
    
    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: any MTLCommandBuffer)
    {

        context.graphRenderer?.execute(graph: self.subGraph,
                                       executionContext: context,
                                       renderPassDescriptor: renderPassDescriptor,
                                       commandBuffer: commandBuffer,
                                       clearFlags: false)

        // Forward outlet values from inner ports to proxy ports so the
        // parent graph receives sub graph outputs.
        for port in self.proxyPorts where port.kind == .Outlet
        {
            (port as? any ProxyPortProtocol)?.forwardFromInner()
        }
    }    
}
