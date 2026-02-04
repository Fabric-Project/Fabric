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
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override public class var nodeDescription: String { "Execute a Sub Graph n number of times"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputIteratonCount", ParameterPort(parameter: IntParameter("Iterations", 0, 100, 2, .inputfield, "Number of times to execute the subgraph"))),
        ]
    }
    
    // Port Proxy
    public var inputIteratonCount:ParameterPort<Int> { port(named: "inputIteratonCount") }
        
    // Ensure we always render!
    override public var isDirty:Bool { get {  true  } set { } }

    var renderProxy:SubgraphIteratorRenderable

    override public var object:Object? {
        return self.renderProxy
    }

    public required init(context: Context)
    {
        self.renderProxy = SubgraphIteratorRenderable(iterationCount: 1)

        super.init(context: context)
        
        self.renderProxy.subGraph = self.subGraph
    }
    
    public required init(from decoder: any Decoder) throws
    {
        self.renderProxy = SubgraphIteratorRenderable(iterationCount: 1)

        try super.init(from: decoder)
        
        self.renderProxy.subGraph = self.subGraph
    }
    
    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: any MTLCommandBuffer)
    {
        
        self.renderProxy.graphContext = context
        self.renderProxy.currentRenderPass = renderPassDescriptor
        self.renderProxy.currentCommandBuffer = commandBuffer
//        self.renderProxy.renderables = self.subGraph.renderables

        if self.inputIteratonCount.valueDidChange,
            let count = self.inputIteratonCount.value
        {
            self.renderProxy.iterationCount = count
        }
        
        // execute the graph once, to just ensure meshes / materials have latest values popogated to nodes
        // this does technically introduce one additional draw call
        // Not sure the best way to avoid this - since we need to have the graph 'configured'
//        self.renderProxy.execute(context: context, renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer,)
        
      
    }
}
