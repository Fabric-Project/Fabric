//
//  NumerRemapRange.swift
//  Fabric
//
//  Created by Anton Marini on 5/22/25.
//

import Foundation
import Satin
import Metal
internal import Noise

public class GradientNoiseNode : Node, NodeProtocol
{
    public static let name = "Gradient Noise"
    public static var nodeType = Node.NodeType.Parameter(parameterType: .Number)

    // Params
    public let inputFrequency:FloatParameter
//    let inputMinNumber:GenericParameter<Float>
//    let inputMaxNumber:GenericParameter<Float>
//    let inputNewMinNumber:GenericParameter<Float>
//    let inputNewMaxNumber:GenericParameter<Float>

    public override var inputParameters:[any Parameter]  { super.inputParameters + [ inputFrequency ] }

    // Ports
    public let outputNumber:NodePort<Float>
    public override var ports: [any NodePortProtocol] { super.ports + [ outputNumber] }

    // Ensure we always render!
    public override var isDirty:Bool { get {  true  } set { } }

    
    private let fbm = GradientNoise2D(amplitude: 1.0, frequency: 1.0, seed: time(nil) )
    
    public required init(context: Context) {
        self.inputFrequency = FloatParameter("Frequency", 1.0, 0.0, 10.0, .slider)
        
        self.outputNumber = NodePort<Float>(name: "Output Number" , kind: .Outlet)
        
        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputFrquencyParameter
        case outputNumberPort
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputFrequency, forKey: .inputFrquencyParameter)

        try container.encode(self.outputNumber, forKey: .outputNumberPort)
        
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputFrequency = try container.decode(FloatParameter.self, forKey: .inputFrquencyParameter)
        self.outputNumber = try container.decode(NodePort<Float>.self, forKey: .outputNumberPort)
        
        try super.init(from: decoder)
    }
    
    public override func execute(context:GraphExecutionContext,
                                  renderPassDescriptor: MTLRenderPassDescriptor,
                                  commandBuffer: MTLCommandBuffer)
    {
        //self.fbm.frequency_scaled(by: Double(self.inputFrequency.value) )
        
        self.outputNumber.send( Float( self.fbm.evaluate(context.timing.time, 0.0) )  )
    }
}
