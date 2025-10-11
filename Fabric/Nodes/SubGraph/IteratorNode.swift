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

    
    public required init(context: Context)
    {
        self.inputIteratonCount = IntParameter("Iterations", 0, 1000, 2, .inputfield)
        super.init(context: context)

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

        try super.init(from: decoder)
        
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
        
        if self.inputIteratonCount.valueDidChange
        {
            self.renderProxy.iterationCount = self.inputIteratonCount.value
        }
        
        self.renderProxy.execute(context: context, renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
        
//        let colorLoad =  context.graphRenderer?.renderer.colorLoadAction
//        context.graphRenderer?.renderer.colorLoadAction = .load
//        
//        let depthLoad =  context.graphRenderer?.renderer.depthLoadAction
//        context.graphRenderer?.renderer.depthLoadAction = .load

//        for iteration in 0 ..< self.inputIteratonCount.value
//        {
//            let iterationInfo = GraphIterationInfo(iteratorNodeID: self.id,
//                                                   totalIterationCount: self.inputIteratonCount.value,
//                                                   currentIteration: iteration)
//            
//            context.iterationInfo = iterationInfo
//            
//            let _ = context.graphRenderer?.execute(graph: self.graph,
//                                                   executionContext: context,
//                                                   renderPassDescriptor: renderPassDescriptor,
//                                                   commandBuffer: commandBuffer)
//            
//            // ??
//            self.graph.recursiveMarkDirty()
//        }
//        
//        context.iterationInfo = nil
////        context.graphRenderer?.renderer.colorLoadAction = colorLoad ?? .clear
////        context.graphRenderer?.renderer.depthLoadAction = depthLoad ?? .clear


    }
    
}
