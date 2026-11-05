//
//  IteratorInfoNode.swift
//  Fabric
//
//  Created by Anton Marini on 5/2/25.
//

import Foundation
import Satin
import simd
import Metal

public class IteratorInfoNode : Node
{
    public override class var name:String { "Iterator Info" }
    public override class var nodeType:Node.NodeType { Node.NodeType.Subgraph }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeDescription: String { "Reports information of the current iteration"}

    public override var isDirty:Bool { get {  true  } set { } }
    
    // Ports
    public let outputProgress = NodePort<Float>(name: "Iterator Progress", kind: .Outlet)
    public let outputIndex = NodePort<Int>(name: "Current Iteration", kind: .Outlet)
    public let outputIterationCount = NodePort<Int>(name: "Number of Iterations", kind: .Outlet)

    public override func declaredPorts() -> [PortDeclaration]
    {
        [
            PortDeclaration(key: "outputProgressPort", port: self.outputProgress),
            PortDeclaration(key: "outputIndexPort", port: self.outputIndex),
            PortDeclaration(key: "outputIterationCountPort", port: self.outputIterationCount),
        ] + super.declaredPorts()
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
//        print("Iterator Info executing")
        if let iterationInfo = executionInfo.iterationInfo
        {
            self.outputProgress.send( iterationInfo.normalizedCurrentIteration)
            self.outputIndex.send( iterationInfo.currentIteration)
            self.outputIterationCount.send( iterationInfo.totalIterationCount)
        }
        
    }
}
