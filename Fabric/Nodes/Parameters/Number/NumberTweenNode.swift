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

public class NumberEaseNode : Node, NodeProtocol
{
    public static let name = "Number Ease"
    public static var nodeType = Node.NodeType.Parameter(parameterType: .Number)

    // Params
    public let inputTimeParam:FloatParameter
    public let inputEasingParam:StringParameter
    public override var inputParameters:[any Parameter]  { super.inputParameters + [inputTimeParam, inputEasingParam] }

    // Ports
    public let outputNumber:NodePort<Float>
    public override var ports: [any NodePortProtocol] { super.ports + [ outputNumber] }

    private let easingMap = Dictionary(uniqueKeysWithValues: zip(Easing.allCases.map( {$0.title()}), Easing.allCases)  )
    
    public required init(context: Context)
    {
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
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputTimeParam, forKey: .inputTimeParameter)
        try container.encode(self.inputEasingParam, forKey: .inputEasingParameter)
        try container.encode(self.outputNumber, forKey: .outputNumberPort)
        
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputTimeParam = try container.decode(FloatParameter.self, forKey: .inputTimeParameter)
        self.inputEasingParam = try container.decode(StringParameter.self, forKey: .inputEasingParameter)
        
        self.inputEasingParam.options = Easing.allCases.map( {$0.title()} )
        
        self.outputNumber = try container.decode(NodePort<Float>.self, forKey: .outputNumberPort)
        
        try super.init(from: decoder)
    }
    
    public override func evaluate(atTime:TimeInterval,
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
