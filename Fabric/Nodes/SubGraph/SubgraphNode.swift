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

public class SubgraphNode: Node
{
    override public class var name:String { "Sub Graph" }
    override public class var nodeType:Node.NodeType { Node.NodeType.Subgraph }

    let graph:Graph
    
    override public var ports:[AnyPort] { self.graph.publishedPorts() }
    
    public required init(context: Context)
    {
        self.graph = Graph(context: context)
        
        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case subGraph
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.graph, forKey: .subGraph)
        
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.graph = try container.decode(Graph.self, forKey: .subGraph)
                
        try super.init(from: decoder)
    }
    
    override public var isDirty: Bool
    {
        self.graph.needsExecution
    }
    
    override public func markClean()
    {
        for node in self.graph.nodes
        {
            node.markClean()
        }
    }
         
    override public func markDirty()
    {
        for node in self.graph.nodes
        {
            node.markDirty()
        }
    }
    
    override public func startExecution(context:GraphExecutionContext)
    {
        context.graphRenderer?.startExecution(graph: self.graph)
    }
    
    override public func stopExecution(context:GraphExecutionContext)
    {
        context.graphRenderer?.stopExecution(graph: self.graph)
    }

    override public func enableExecution(context:GraphExecutionContext)
    {
        context.graphRenderer?.enableExecution(graph: self.graph)
    }
    
    override public func disableExecution(context:GraphExecutionContext)
    {
        context.graphRenderer?.disableExecution(graph: self.graph)
    }
    
    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: any MTLCommandBuffer)
    {

        // this isnt great, as we need to surface the objects to be in the parent graphs
        context.graphRenderer?.execute(graph: self.graph, executionContext: context, renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
//        self.graphRenderer.execute(graph: self.graph,
//                                   executionContext: context,
//                                   renderPassDescriptor: renderPassDescriptor,
//                                   commandBuffer: commandBuffer)
    }
    
}
