//
//  FloatTween.swift
//  Fabric
//
//  Created by Anton Marini on 4/26/25.
//


import Foundation
import Satin
import simd
import Metal

class NumberEaseNode : Node, NodeProtocol
{
    static let name = "Number Ease"
    static var nodeType = Node.NodeType.Parameter

    // Params
    let inputTimeParam:FloatParameter
    let inputEasingParam:StringParameter
    override var inputParameters:[any Parameter]  { super.inputParameters + [inputTimeParam, inputEasingParam] }

    // Ports
    let outputNumber:NodePort<Float>
    override var ports: [any NodePortProtocol] { super.ports + [ outputNumber] }

    private let easingMap = Dictionary(uniqueKeysWithValues: zip(Easing.allCases.map( {$0.title()}), Easing.allCases)  )
    
    required init(context: Context) {
        self.inputTimeParam = FloatParameter("Time", 0.0, 0.0, 1.0, .slider)
        self.inputEasingParam = StringParameter("Easing", "Linear", Easing.allCases.map( {$0.title()} ), .dropdown )
        
        self.outputNumber = NodePort<Float>(name: "Output Number" , kind: .Outlet)
        
        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputTimeParameter
        case inputEasingParameter
        case outputNumberPort
    }
    
    override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputTimeParam, forKey: .inputTimeParameter)
        try container.encode(self.inputEasingParam, forKey: .inputEasingParameter)
        try container.encode(self.outputNumber, forKey: .outputNumberPort)
        
        try super.encode(to: encoder)
    }
    
    required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputTimeParam = try container.decode(FloatParameter.self, forKey: .inputTimeParameter)
        self.inputEasingParam = try container.decode(StringParameter.self, forKey: .inputEasingParameter)
        
        self.inputEasingParam.options = Easing.allCases.map( {$0.title()} )
        
        self.outputNumber = try container.decode(NodePort<Float>.self, forKey: .outputNumberPort)
        
        try super.init(from: decoder)
    }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        
        
        let loopedTime = self.inputTimeParam.value//.truncatingRemainder(dividingBy: duration)

        if let easeFunc = easingMap[self.inputEasingParam.value]
        {
            
            self.outputNumber.send( Float( easeFunc.function( Double(loopedTime) ) ) )

        }
        else
        {
            self.outputNumber.send( loopedTime )
        }
        
       
     }
}
