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
        self.renderProxy = SubgraphIteratorRenderable(context:context, iterationCount: 1)

        super.init(context: context)
        
        self.renderProxy.subGraph = self.subGraph
    }
    
    public required init(from decoder: any Decoder) throws
    {
        guard let context = decoder.context?.documentContext as? Context else { fatalError("Unable to get document context") }
        
        self.renderProxy = SubgraphIteratorRenderable(context:context, iterationCount: 1)

        try super.init(from: decoder)
        
        self.renderProxy.subGraph = self.subGraph
    }
    
    override public func startExecution(renderer:GraphRenderer)
    {
        self.renderProxy.startExecution(renderer:renderer)
    }
    
    override public func stopExecution(renderer:GraphRenderer)
    {
        self.renderProxy.stopExecution(renderer: renderer)
    }

    override public func enableExecution(renderer:GraphRenderer)
    {
        self.renderProxy.enableExecution(renderer: renderer)
    }
    
    override public func disableExecution(renderer:GraphRenderer)
    {
        self.renderProxy.disableExecution(renderer: renderer)
    }
    
    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        self.renderProxy.graphRenderer = renderer
        self.renderProxy.graphExecutionInfo = executionInfo
        self.renderProxy.currentRenderPass = renderPassDescriptor
        self.renderProxy.currentCommandBuffer = commandBuffer

        if let count = self.inputIteratonCount.value
        {
            self.renderProxy.iterationCount = count
        }

        // execute the graph once, to just ensure meshes / materials have latest values popogated to nodes
        // this does technically introduce one additional draw call
        // Not sure the best way to avoid this - since we need to have the graph 'configured'
        self.renderProxy.execute(renderer: renderer, executionInfo: executionInfo, renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)

        // We need to call this to ensure any published port values also get forwarded.
        self.forwardPortValues(force:true)
    }
}
