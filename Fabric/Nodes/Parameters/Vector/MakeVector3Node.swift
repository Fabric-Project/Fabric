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

public class MakeVector3Node : Node
{
    override public static var name:String { "Vector 3" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .Vector) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Converts 4 numcerical components to a Vector 4"}
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputXParam", ParameterPort(parameter: FloatParameter("X", 0.0, .inputfield, "X component of the vector"))),
            ("inputYParam", ParameterPort(parameter: FloatParameter("Y", 0.0, .inputfield, "Y component of the vector"))),
            ("inputZParam", ParameterPort(parameter: FloatParameter("Z", 0.0, .inputfield, "Z component of the vector"))),
            ("outputVector", NodePort<simd_float3>(name: "Vector 3" , kind: .Outlet, description: "Combined 3D vector from X, Y and Z components")),
        ]
    }
    
    // Port Proxy
    public var inputXParam:ParameterPort<Float> { port(named: "inputXParam") }
    public var inputYParam:ParameterPort<Float> { port(named: "inputYParam") }
    public var inputZParam:ParameterPort<Float> { port(named: "inputZParam") }
    public var outputVector:NodePort<simd_float3> { port(named: "outputVector") }
        
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputXParam.valueDidChange || self.inputYParam.valueDidChange || self.inputZParam.valueDidChange,
           let x = self.inputXParam.value,
           let y = self.inputYParam.value,
           let z = self.inputZParam.value
        {
            self.outputVector.send( simd_float3(x,y,z) )
        }
    }
}
