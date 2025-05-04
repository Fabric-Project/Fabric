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

class MakeVector4Node : Node, NodeProtocol
{
    static let name = "Vector 4"
    static var nodeType = Node.NodeType.Parameter

    let outputVector = NodePort<simd_float4>(name: "Vector 4" , kind: .Outlet)

    // Params
    let inputXParam = FloatParameter("X", 0.0, -10, 10, .slider)
    let inputYParam = FloatParameter("Y", 0.0, -10, 10, .slider)
    let inputZParam = FloatParameter("Z", 0.0, -10, 10, .slider)
    let inputWParam = FloatParameter("W", 0.0, -10, 10, .slider)

    override var inputParameters: [any Parameter] {  [inputXParam, inputYParam, inputZParam, inputWParam]}
    
    private var vector = simd_float4(repeating: 0)
    
    override var ports: [any AnyPort] { super.ports + [outputVector] }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        self.vector = simd_float4(inputXParam.value,
                                  inputYParam.value,
                                  inputZParam.value,
                                  inputWParam.value)

        self.outputVector.send( self.vector )
     }
}
