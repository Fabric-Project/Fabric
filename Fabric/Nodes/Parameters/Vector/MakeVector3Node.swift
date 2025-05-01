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

class MakeVector3Node : Node, NodeProtocol
{
    static let name = "Vector 3"
    static var nodeType = Node.NodeType.Parameter

    // Ports
    let inputX = NodePort<Float>(name: "X" , kind: .Inlet)
    let inputY = NodePort<Float>(name: "Y" , kind: .Inlet)
    let inputZ = NodePort<Float>(name: "Z" , kind: .Inlet)

    let outputVector = NodePort<simd_float3>(name: "Vector 3" , kind: .Outlet)

    // Params
    let inputXParam = FloatParameter("X", 1.0, -10, 10, .slider)
    let inputYParam = FloatParameter("Y", 1.0, -10, 10, .slider)
    let inputZParam = FloatParameter("Z", 1.0, -10, 10, .slider)

    override var inputParameters: [any Parameter] {  [inputXParam, inputYParam, inputZParam]}
    
    private var vector = simd_float3(repeating: 0)
    
    override var ports: [any AnyPort] { super.ports + [outputVector] }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        if let v = self.inputX.value {
            vector.x = v
        }
        
        if let v = self.inputY.value {
            vector.y = v
        }
        
        if let v = self.inputZ.value {
            vector.z = v
        }
               
        
        self.outputVector.send( self.vector )
     }
}
