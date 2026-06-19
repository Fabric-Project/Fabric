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
    public let outputProgress:NodePort<Float>
    public let outputIndex:NodePort<Int>
    public let outputIterationCount:NodePort<Int>
    public override var ports: [Port] { [ outputProgress, outputIndex, outputIterationCount] + super.ports}
    
    public required init(context: Context)
    {
        self.outputProgress =  NodePort<Float>(name: "Iterator Progress" , kind: .Outlet)
        self.outputIndex =  NodePort<Int>(name: "Current Iteration" , kind: .Outlet)
        self.outputIterationCount =  NodePort<Int>(name: "Number of Iterations" , kind: .Outlet)

        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case outputProgressPort
        case outputIndexPort
        case outputIterationCountPort
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.outputProgress, forKey: .outputProgressPort)
        try container.encode(self.outputIndex, forKey: .outputIndexPort)
        try container.encode(self.outputIterationCount, forKey: .outputIterationCountPort)

        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.outputProgress = try container.decode(NodePort<Float>.self, forKey: .outputProgressPort)
        self.outputIndex = try container.decode(NodePort<Int>.self, forKey: .outputIndexPort)
        self.outputIterationCount = try container.decode(NodePort<Int>.self, forKey: .outputIterationCountPort)

        try super.init(from: decoder)
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
//        print("Iterator Info executing")
        if let iterationInfo = context.iterationInfo
        {
//            print("Iterator Info Sending Iteration Info for iteration \(iterationInfo.normalizedCurrentIteration)  \(iterationInfo.currentIteration) of \(iterationInfo.totalIterationCount) )")
            self.outputProgress.send( iterationInfo.normalizedCurrentIteration)
            self.outputIndex.send( iterationInfo.currentIteration)
            self.outputIterationCount.send( iterationInfo.totalIterationCount)
        }
        
    }
}
