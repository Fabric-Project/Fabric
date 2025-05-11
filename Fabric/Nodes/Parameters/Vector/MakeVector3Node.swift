//
//  MakeVector4Node.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//

import Foundation
import Satin
import simd
import Metal

class MakeVector3Node : Node, NodeProtocol
{
    static let name = "Vector 3"
    static var nodeType = Node.NodeType.Parameter

    // Params
    let inputXParam:FloatParameter
    let inputYParam:FloatParameter
    let inputZParam:FloatParameter
    override var inputParameters: [any Parameter] {  [inputXParam, inputYParam, inputZParam]}
    
    // Ports
    let outputVector:NodePort<simd_float3>
    override var ports: [any NodePortProtocol] { super.ports + [outputVector] }

    private var vector = simd_float3(repeating: 0)

    required init(context: Context)
    {
        self.inputXParam = FloatParameter("X", 0.0, .inputfield)
        self.inputYParam = FloatParameter("Y", 0.0, .inputfield)
        self.inputZParam = FloatParameter("Z", 0.0, .inputfield)
        self.outputVector = NodePort<simd_float3>(name: "Vector 3" , kind: .Outlet)
        
        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case inputXParameter
        case inputYParameter
        case inputZParameter
        case outputVectorPort
    }
    
    override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputXParam, forKey: .inputXParameter)
        try container.encode(self.inputYParam, forKey: .inputYParameter)
        try container.encode(self.inputZParam, forKey: .inputZParameter)
        try container.encode(self.outputVector, forKey: .outputVectorPort)
        
        try super.encode(to: encoder)
    }
    
    required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputXParam = try container.decode(FloatParameter.self, forKey: .inputXParameter)
        self.inputYParam = try container.decode(FloatParameter.self, forKey: .inputYParameter)
        self.inputZParam = try container.decode(FloatParameter.self, forKey: .inputZParameter)
        self.outputVector = try container.decode(NodePort<simd_float3>.self, forKey: .outputVectorPort)
        
        try super.init(from: decoder)
    }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        self.vector = simd_float3(inputXParam.value,
                                  inputYParam.value,
                                  inputZParam.value)
        
        self.outputVector.send( self.vector )
     }
}
