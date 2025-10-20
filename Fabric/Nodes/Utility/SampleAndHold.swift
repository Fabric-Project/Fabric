//
//  SampleAndHold.swift
//  Fabric
//
//  Created by Anton Marini on 10/16/25.
//

import Foundation
import Satin
import Metal
import simd

public class SampleAndHold<ValueType : FabricPort & Equatable & FabricDescription> : Node
{
    public override class var name:String { "Sample and Hold \(ValueType.fabricDescription)" }
    public override class var nodeType:Node.NodeType { Node.NodeType.Utility }

    // Params
    public let inputSample:BoolParameter
    public let inputReset:BoolParameter
    public override var inputParameters: [any Parameter] { [inputSample, inputReset] + super.inputParameters }
    
    // Ports
    public let inputValue:NodePort<ValueType>
    public let outputValue:NodePort<ValueType>
    
    private var value:ValueType?
    
    public override var ports: [Port] { [ self.inputValue, self.outputValue ] + super.ports}
    
    public required init(context: Context)
    {
        self.inputSample = BoolParameter("Sample", true)
        self.inputReset = BoolParameter("Reset", false)

        self.inputValue = NodePort<ValueType>(name: "Value" , kind: .Inlet)
        self.outputValue = NodePort<ValueType>(name: "Value" , kind: .Outlet)

        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputValuePort
        case inputSampleParam
        case inputResetParam
        case outputValuePort
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputValue, forKey: .inputValuePort)
        try container.encode(self.inputSample, forKey: .inputSampleParam)
        try container.encode(self.inputReset, forKey: .inputResetParam)
        try container.encode(self.outputValue, forKey: .outputValuePort)

        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputValue = try container.decode(NodePort<ValueType>.self, forKey: .inputValuePort)
        self.inputSample = try container.decode(BoolParameter.self, forKey: .inputSampleParam)
        self.inputReset = try container.decode(BoolParameter.self, forKey: .inputResetParam)

        self.outputValue = try container.decode(NodePort<ValueType>.self, forKey: .outputValuePort)

        try super.init(from: decoder)
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        
        if self.inputValue.valueDidChange
        {
            if self.inputSample.value
            {
                self.value = self.inputValue.value

                self.outputValue.send(self.value)
            }
        }
        
        if self.inputReset.valueDidChange
        {
            if self.inputReset.value
            {
                self.value = nil
                self.outputValue.send(self.value)
            }
        }
        
    }
}
