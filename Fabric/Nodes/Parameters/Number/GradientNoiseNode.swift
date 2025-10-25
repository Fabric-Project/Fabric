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

public class GradientNoiseNode : Node
{
    override public static var name:String { "Gradient Noise" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Provide a Smooth Gradient based Random Number"}
   
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputTime", ParameterPort(parameter:  FloatParameter("Time", 0.0, .inputfield))),
            ("inputFrequency", ParameterPort(parameter:  FloatParameter("Frequency", 1.0, 0.0, 10.0, .slider))),
            ("outputNumber", NodePort<Float>(name: NumberNode.name , kind: .Outlet)),
        ]
    }
    
    // Port Proxy
    public var inputTime:ParameterPort<Float> { port(named: "inputTime") }
    public var inputFrequency:ParameterPort<Float> { port(named: "inputFrequency") }
    public var outputNumber:NodePort<Float> { port(named: "outputNumber") }
    
    // Ensure we always render!
    public override var isDirty:Bool { get {  true  } set { } }

    private var fbm = GradientNoise2D(amplitude: 1.0, frequency: 1.0, seed: time(nil) )
    
   
    public override func execute(context:GraphExecutionContext,
                                  renderPassDescriptor: MTLRenderPassDescriptor,
                                  commandBuffer: MTLCommandBuffer)
    {
        //self.fbm.frequency_scaled(by: Double(self.inputFrequency.value) )
        if self.inputFrequency.valueDidChange,
           let frequencyValue = self.inputFrequency.value
        {
            self.fbm = GradientNoise2D(amplitude: 1.0, frequency: Double(frequencyValue), seed: time(nil) )
        }
        
        if self.inputTime.valueDidChange,
           let time = self.inputTime.value
        {
            self.outputNumber.send( Float( self.fbm.evaluate( Double(time), 0.0) ) )
        }
    }
}
