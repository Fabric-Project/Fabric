//
//  MakeQuaternionNode.swift
//  Fabric
//
//  Created by Anton Marini on 5/4/25.
//

import Foundation
import Satin
import simd
import Metal

public class MakeQuaternionNode : Node
{
    override public class var name:String { "Quaternion" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Quaternion) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Create a Quaternion from an Angle and Axis"}
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [

            // Params
             ("inputAngle", ParameterPort(parameter: FloatParameter("Angle", 0.0, .inputfield))),
             ("inputAxis", ParameterPort(parameter: Float3Parameter("Axis", simd_float3(0, 1, 0), .inputfield))),
             
             ("outputQuaterinion", NodePort<simd_float4>(name: "Quaternion" , kind: .Outlet))
        ]
    }
    
    // Port Proxy
    public var inputAngle:NodePort<Float> { port(named: "inputAngle") }
    public var inputAxis:NodePort<simd_float3> { port(named: "inputAxis") }
    public var outputQuaterinion:NodePort<simd_float4> { port(named: "outputQuaterinion") }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputAngle.valueDidChange || self.inputAxis.valueDidChange,
           let inputAngleValue = self.inputAngle.value,
           let inputAxisValue = self.inputAxis.value
        {
            let quat = simd_quatf(angle: inputAngleValue * .pi / 180,
                                  axis: inputAxisValue ).normalized

            self.outputQuaterinion.send( quat.vector )
        }
    }
}
