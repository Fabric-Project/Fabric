//
//  NumberRemapRange.swift
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
    public let inputTime = ParameterPort(parameter:  FloatParameter("Time", 0.0, .inputfield, "Time value to sample the noise function"))
    public let inputFrequency = ParameterPort(parameter:  FloatParameter("Frequency", 1.0, 0.0, 10.0, .slider, "Frequency of the noise pattern (higher = more variation)"))
    public let outputNumber = NodePort<Float>(name: "Number" , kind: .Outlet, description: "Smooth random noise value")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputTime", port: self.inputTime),
            PortDeclaration(key: "inputFrequency", port: self.inputFrequency),
            PortDeclaration(key: "outputNumber", port: self.outputNumber),
        ]
    }

    // Ensure we always render!
    public override var isDirty:Bool { get {  true  } set { } }

    private var fbm = GradientNoise2D(amplitude: 1.0, frequency: 1.0, seed: time(nil) )
    
   
    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
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
