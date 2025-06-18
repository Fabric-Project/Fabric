//
//  NumerRemapRange.swift
//  Fabric
//
//  Created by Anton Marini on 5/22/25.
//

import Foundation
import Satin
import Metal

class NumberRemapNode : Node, NodeProtocol
{
    static let name = "Number Remap"
    static var nodeType = Node.NodeType.Parameter(parameterType: .Number)

    // Params
    let inputNumber:GenericParameter<Float>
    let inputMinNumber:GenericParameter<Float>
    let inputMaxNumber:GenericParameter<Float>
    let inputNewMinNumber:GenericParameter<Float>
    let inputNewMaxNumber:GenericParameter<Float>

    override var inputParameters:[any Parameter]  { super.inputParameters + [inputNumber,
                                                                             inputMinNumber,
                                                                             inputMaxNumber,
                                                                             inputNewMinNumber,
                                                                             inputNewMaxNumber,
    ] }

    // Ports
    let outputNumber:NodePort<Float>
    override var ports: [any NodePortProtocol] { super.ports + [ outputNumber] }

    private let easingMap = Dictionary(uniqueKeysWithValues: zip(Easing.allCases.map( {$0.title()}), Easing.allCases)  )
    
    required init(context: Context) {
        self.inputNumber = GenericParameter<Float>("Number", 0.0, .inputfield)
        self.inputMinNumber = GenericParameter<Float>("Input Min", 0.0, .inputfield)
        self.inputMaxNumber = GenericParameter<Float>("Input Max", 1.0, .inputfield)
        self.inputNewMinNumber = GenericParameter<Float>("Output Min", 0.0, .inputfield)
        self.inputNewMaxNumber = GenericParameter<Float>("Output Max", 1.0, .inputfield)
        
        self.outputNumber = NodePort<Float>(name: "Output Number" , kind: .Outlet)
        
        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputNumberParam
        case inputMinNumberParam
        case inputMaxNumberParam
        case inputNewMinNumberParam
        case inputNewMaxNumberParam
        case outputNumberPort
    }
    
    override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputNumber, forKey: .inputNumberParam)
        try container.encode(self.inputMinNumber, forKey: .inputMinNumberParam)
        try container.encode(self.inputMaxNumber, forKey: .inputMaxNumberParam)
        try container.encode(self.inputNewMinNumber, forKey: .inputNewMinNumberParam)
        try container.encode(self.inputNewMaxNumber, forKey: .inputNewMaxNumberParam)

        try container.encode(self.outputNumber, forKey: .outputNumberPort)
        
        try super.encode(to: encoder)
    }
    
    required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputNumber = try container.decode(GenericParameter<Float>.self, forKey: .inputNumberParam)
        self.inputMinNumber = try container.decode(GenericParameter<Float>.self, forKey: .inputMinNumberParam)
        self.inputMaxNumber = try container.decode(GenericParameter<Float>.self, forKey: .inputMaxNumberParam)
        self.inputNewMinNumber = try container.decode(GenericParameter<Float>.self, forKey: .inputNewMinNumberParam)
        self.inputNewMaxNumber = try container.decode(GenericParameter<Float>.self, forKey: .inputNewMaxNumberParam)

        self.outputNumber = try container.decode(NodePort<Float>.self, forKey: .outputNumberPort)
        
        try super.init(from: decoder)
    }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        self.outputNumber.send( remap(self.inputNumber.value,
                                      self.inputMinNumber.value,
                                      self.inputMaxNumber.value,
                                      self.inputNewMinNumber.value,
                                      self.inputNewMaxNumber.value) )
    }
}
