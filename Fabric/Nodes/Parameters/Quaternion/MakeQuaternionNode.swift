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

public class MakeQuaternionNode : Node, NodeProtocol
{
    public static let name = "Quaternion"
    public static var nodeType = Node.NodeType.Parameter

    let outputVector = NodePort<simd_quatf>(name: "Quaternion" , kind: .Outlet)

    // Params
    let inputAngle = FloatParameter("Angle", 0.0, -180, 180, .slider)
    let inputAxisParam = Float3Parameter("Axis", simd_float3(0, 1, 0) )

    override public var inputParameters: [any Parameter] {  [inputAngle, inputAxisParam] + super.inputParameters}
    
    private var quat = simd_quatf(angle: 0, axis: simd_float3(0, 1, 0))
    
    override public var ports:[AnyPort] {  [outputVector] + super.ports }
    
    override public  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        self.outputVector.send( simd_quatf(angle: self.inputAngle.value * .pi / 180,
                                           axis: self.inputAxisParam.value ) )
     }
}
