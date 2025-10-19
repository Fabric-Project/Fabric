//
//  Vector3ToFloatNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/16/25.
//

import Foundation
import Satin
import simd
import Metal

public class Vector3ToFloatNode : Node
{
    override public static var name:String { "Vector 3 to Float" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .Vector) }

    // Params
    public let inputVectorParam:Float3Parameter
    public override var inputParameters: [any Parameter] { [inputVectorParam] + super.inputParameters}
    
    // Ports
    public let outputXPort:NodePort<Float>
    public let outputYPort:NodePort<Float>
    public let outputZPort:NodePort<Float>
    public override var ports: [Port] { [outputXPort, outputYPort, outputZPort] + super.ports}

    public required init(context: Context)
    {
        self.inputVectorParam = Float3Parameter("Vector 3", .zero, .inputfield)
        self.outputXPort = NodePort<Float>(name: "X" , kind: .Outlet)
        self.outputYPort = NodePort<Float>(name: "Y" , kind: .Outlet)
        self.outputZPort = NodePort<Float>(name: "Z" , kind: .Outlet)

        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case inputVectorParam
        case outputXPort
        case outputYPort
        case outputZPort
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputVectorParam, forKey: .inputVectorParam)
        try container.encode(self.outputXPort, forKey: .outputXPort)
        try container.encode(self.outputYPort, forKey: .outputYPort)
        try container.encode(self.outputZPort, forKey: .outputZPort)

        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputVectorParam = try container.decode(Float3Parameter.self, forKey: .inputVectorParam)
        self.outputXPort = try container.decode(NodePort<Float>.self, forKey: .outputXPort)
        self.outputYPort = try container.decode(NodePort<Float>.self, forKey: .outputYPort)
        self.outputZPort = try container.decode(NodePort<Float>.self, forKey: .outputZPort)
        
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
            self.outputZPort.send( inputVectorParam.value.z )
        }
     }
}
