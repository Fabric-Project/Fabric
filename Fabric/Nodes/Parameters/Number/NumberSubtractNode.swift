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

class NumberSubtractNode : Node, NodeProtocol
{
    static let name = "Number Subtract"
    static var nodeType = Node.NodeType.Parameter(parameterType: .Number)

    // Params
    let inputAParam:FloatParameter
    let inputBParam:FloatParameter
    override var inputParameters:[any Parameter] { super.inputParameters + [inputAParam, inputBParam] }

    // Ports
    let outputNumber:NodePort<Float>
    override var ports: [any NodePortProtocol] { super.ports + [ outputNumber] }

    required init(context: Context)
    {
        self.inputAParam = FloatParameter("A", 0.0, .inputfield)
        self.inputBParam = FloatParameter("B", 0.0, .inputfield)
        self.outputNumber = NodePort<Float>(name: NumberSubtractNode.name , kind: .Outlet)
        
        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case inputAParameter
        case inputBParameter
        case outputNumberPort
    }
    
    override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputAParam, forKey: .inputAParameter)
        try container.encode(self.inputBParam, forKey: .inputBParameter)
        try container.encode(self.outputNumber, forKey: .outputNumberPort)
        
        try super.encode(to: encoder)
    }
    
    required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputAParam = try container.decode(FloatParameter.self, forKey: .inputAParameter)
        self.inputBParam = try container.decode(FloatParameter.self, forKey: .inputBParameter)
        self.outputNumber = try container.decode(NodePort<Float>.self, forKey: .outputNumberPort)
        
        try super.init(from: decoder)
    }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        
       
        self.outputNumber.send(self.inputAParam.value - self.inputBParam.value )
     }
}
