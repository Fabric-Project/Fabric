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

public class IteratorNode: SubgraphNode
{
    public override class var name:String { "Iterator" }
    
    // Parameters:
    public let inputIteratonCount:IntParameter
    
    public override var inputParameters: [any Parameter] {
        [inputIteratonCount]
        + super.inputParameters }


    // Ensure we always render!
    public override var isDirty:Bool { get {  true  } set { } }

    var renderProxy:SubgraphIteratorRenderable

    public required init(context: Context)
    {
        self.inputIteratonCount = IntParameter("Iterations", 0, 100, 2, .inputfield)
        self.renderProxy = SubgraphIteratorRenderable(iterationCount: 1)

        super.init(context: context)
        
        self.renderProxy.subGraph = self.graph
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputIteratonCount
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputIteratonCount, forKey: .inputIteratonCount)
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.inputIteratonCount = try container.decode(IntParameter.self , forKey:.inputIteratonCount)
        self.renderProxy = SubgraphIteratorRenderable(iterationCount: 1)

        try super.init(from: decoder)
        
        self.renderProxy.subGraph = self.graph
        
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
        self.renderProxy.graphContext = context
        self.renderProxy.currentRenderPass = renderPassDescriptor
        self.renderProxy.currentCommandBuffer = commandBuffer
        self.renderProxy.renderables = self.graph.renderables

        if self.inputIteratonCount.valueDidChange
        {
            self.renderProxy.iterationCount = self.inputIteratonCount.value
        }
        
        // execute the graph once, to just ensure meshes / materials have latest values popogated to nodes
        self.renderProxy.execute(context: context, renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
        
    }
}
