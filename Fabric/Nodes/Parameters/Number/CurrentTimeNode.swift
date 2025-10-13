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

public class CurrentTimeNode : Node
{
    override public static var name:String { "Current Time" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }

    public override var isDirty:Bool { get {  true  } set { } }

    private let startTime = Date.timeIntervalSinceReferenceDate
    
    // Ports
    public let outputNumber:NodePort<Float>
    public override var ports: [AnyPort] { [ outputNumber] + super.ports}
    
    public required init(context: Context)
    {
        self.outputNumber =  NodePort<Float>(name: CurrentTimeNode.name , kind: .Outlet)

        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case outputNumberPort
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.outputNumber, forKey: .outputNumberPort)
        
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.outputNumber = try container.decode(NodePort<Float>.self, forKey: .outputNumberPort)
        
        try super.init(from: decoder)
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        self.outputNumber.send( Float(context.timing.time - startTime) )
    }
}
