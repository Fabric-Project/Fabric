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

public class MakeVector2Node : Node
{
    override public static var name:String { "Vector 2" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .Vector) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Converts 2 numcerical components to a Vector 2"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputXParam", ParameterPort(parameter: FloatParameter("X", 0.0, .inputfield))),
            ("inputYParam", ParameterPort(parameter: FloatParameter("Y", 0.0, .inputfield))),
            ("outputVector", NodePort<simd_float2>(name: "Vector 2" , kind: .Outlet)),
        ]
    }
    
    // Port Proxy
    public var inputXParam:ParameterPort<Float> { port(named: "inputXParam") }
    public var inputYParam:ParameterPort<Float> { port(named: "inputYParam") }
    public var outputVector:NodePort<simd_float2> { port(named: "outputVector") }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputXParam.valueDidChange || self.inputYParam.valueDidChange,
           let x = self.inputXParam.value,
           let y = self.inputYParam.value
        {
            self.outputVector.send( simd_float2(x,y) )
        }
     }
}
