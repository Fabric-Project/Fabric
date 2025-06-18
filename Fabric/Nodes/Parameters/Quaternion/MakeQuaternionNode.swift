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

class MakeQuaternionNode : Node, NodeProtocol
{
    static let name = "Quaternion"
    static var nodeType = Node.NodeType.Parameter

    let outputVector = NodePort<simd_quatf>(name: "Quaternion" , kind: .Outlet)

    // Params
    let inputAngle = FloatParameter("Angle", 0.0, -180, 180, .slider)
    let inputAxisParam = Float3Parameter("Axis", simd_float3(0, 1, 0) )

    override var inputParameters: [any Parameter] { super.inputParameters + [inputAngle, inputAxisParam,]}
    
    private var quat = simd_quatf(angle: 0, axis: simd_float3(0, 1, 0))
    
    override var ports: [any NodePortProtocol] { super.ports + [outputVector] }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        self.outputVector.send( simd_quatf(angle: self.inputAngle.value * .pi / 180,
                                           axis: self.inputAxisParam.value ) )
     }
}
