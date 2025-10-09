//
//  FloatAddNode.swift
//  Fabric
//
//  Created by Anton Marini on 5/2/25.
//

import Foundation


import Foundation
import Satin
import simd
import Metal

public class IterationInfoNode : Node, NodeProtocol
{
    public static let name = "IterationInfo"
    public static var nodeType = Node.NodeType.Parameter(parameterType: .Number)

    public override var isDirty:Bool { get {  true  } set { } }

    private let startTime = Date.timeIntervalSinceReferenceDate
    
    // Ports
    public let outputProgress:NodePort<Float>
    public override var ports: [any NodePortProtocol] { [ outputProgress] + super.ports}
    
    public required init(context: Context)
    {
        self.outputProgress =  NodePort<Float>(name: CurrentTimeNode.name , kind: .Outlet)

        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case outputProgressPort
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.outputProgress, forKey: .outputProgressPort)
        
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.outputProgress = try container.decode(NodePort<Float>.self, forKey: .outputProgressPort)
        
        try super.init(from: decoder)
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if let iterationInfo = context.iterationInfo
        {
            self.outputProgress.send( iterationInfo.normalizedCurrentIteration )
        }
        
    }
}
