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

class MakeVector2Node : Node, NodeProtocol
{
    static let name = "Vector 2"
    static var nodeType = Node.NodeType.Parameter

    let outputVector = NodePort<simd_float2>(name: "Vector 2" , kind: .Outlet)

    // Params
    let inputXParam = FloatParameter("X", 0.0, -10, 10, .slider)
    let inputYParam = FloatParameter("Y", 0.0, -10, 10, .slider)

    override var inputParameters: [any Parameter] { super.inputParameters + [inputXParam, inputYParam,]}
    
    private var vector = simd_float2(repeating: 0)
    
    override var ports: [any AnyPort] { super.ports + [outputVector] }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        self.vector = simd_float2(inputXParam.value,
                                  inputYParam.value)
        
        self.outputVector.send( self.vector )
     }
}
