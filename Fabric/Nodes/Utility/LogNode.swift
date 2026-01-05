//
//  LogNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/10/25.
//


import Foundation
import Satin
import simd
import Metal




public class LogNode : Node
{
    override public class var name:String { "Log" }
    override public class var nodeType:Node.NodeType { Node.NodeType.Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Log Values to the Console"}

    // Ports
    public let inputAny: NodePort<String>
    public override var ports: [Port] {  [self.inputAny] + super.ports }
    
    public required init(context: Context)
    {
        self.inputAny = NodePort<String>(name: "Log Value" , kind: .Inlet)
        
        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputAnyPort
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputAny, forKey: .inputAnyPort)
        
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputAny = try container.decode(NodePort<String>.self, forKey: .inputAnyPort)
        
        try super.init(from: decoder)
    }
            
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputAny.valueDidChange,
           let value = self.inputAny.value
        {
            print("Frame: \(context.timing.frameNumber): \(value)" )
        }
    }
}
