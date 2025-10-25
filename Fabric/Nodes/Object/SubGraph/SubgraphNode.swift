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
    
    override public var ports:[Port] { self.subGraph.publishedPorts() + super.ports }
    
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
    }
    
    override public var isDirty: Bool
    {
        self.subGraph.needsExecution
    }
    
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

        context.graphRenderer?.execute(graph: self.subGraph, executionContext: context, renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
    }
    
}
