//
//  NumberNode.swift
//  Fabric
//
//  Created by Anton Marini on 5/2/25.
//

import Foundation
import Satin
import simd
import Metal

class NumberIntegralNode : Node, NodeProtocol
{
    static let name = "Number Integral"
    static var nodeType = Node.NodeType.Parameter

    // Params
    let inputNumberParam:FloatParameter

    override var inputParameters:[any Parameter]  { super .inputParameters + [inputNumberParam] }

    // Ports
    let outputNumber:NodePort<Float>
    override var ports: [any NodePortProtocol] { super.ports + [ outputNumber] }
    
    // Ensure we always render!
    override var isDirty:Bool { get {  true  } set { } }

    private var state:Float = 0.0
    
    required init(context: Context)
    {
        self.inputNumberParam = FloatParameter("Number", 0.0, .inputfield)
        self.outputNumber = NodePort<Float>(name: NumberIntegralNode.name , kind: .Outlet)
        
        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case inputNumberParameter
        case outputNumberPort
    }
    
    override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputNumberParam, forKey: .inputNumberParameter)
        try container.encode(self.outputNumber, forKey: .outputNumberPort)
        
        try super.encode(to: encoder)
    }
    
    required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputNumberParam = try container.decode(FloatParameter.self, forKey: .inputNumberParameter)
        self.outputNumber = try container.decode(NodePort<Float>.self, forKey: .outputNumberPort)
        
        try super.init(from: decoder)
    }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        self.state += self.inputNumberParam.value
        
        self.outputNumber.send(self.state)
    }
}
