//
//  Vector2ToFloatNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/16/25.
//

import Foundation
import Satin
import simd
import Metal

public class Vector2ToFloatNode : Node
{
    override public static var name:String { "Vector 2 to Float" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .Vector) }

    // Params
    public let inputVectorParam:Float2Parameter
    public override var inputParameters: [any Parameter] { [inputVectorParam] + super.inputParameters}
    
    // Ports
    public let outputXPort:NodePort<Float>
    public let outputYPort:NodePort<Float>
    public override var ports: [AnyPort] { [outputXPort, outputYPort] + super.ports}

    public required init(context: Context)
    {
        self.inputVectorParam = Float2Parameter("Vector 2", .zero, .inputfield)
        self.outputXPort = NodePort<Float>(name: "X" , kind: .Outlet)
        self.outputYPort = NodePort<Float>(name: "Y" , kind: .Outlet)

        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case inputVectorParam
        case outputXPort
        case outputYPort
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputVectorParam, forKey: .inputVectorParam)
        try container.encode(self.outputXPort, forKey: .outputXPort)
        try container.encode(self.outputYPort, forKey: .outputYPort)

        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputVectorParam = try container.decode(Float2Parameter.self, forKey: .inputVectorParam)
        self.outputXPort = try container.decode(NodePort<Float>.self, forKey: .outputXPort)
        self.outputYPort = try container.decode(NodePort<Float>.self, forKey: .outputYPort)
        
        try super.init(from: decoder)
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputVectorParam.valueDidChange
        {
            self.outputXPort.send( inputVectorParam.value.x )
            self.outputYPort.send( inputVectorParam.value.y )
        }
     }
}
