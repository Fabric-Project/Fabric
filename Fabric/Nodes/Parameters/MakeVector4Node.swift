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

    // Ports
    let inputX = NodePort<Float>(name: "X" , kind: .Inlet)
    let inputY = NodePort<Float>(name: "Y" , kind: .Inlet)
    let inputZ = NodePort<Float>(name: "Z" , kind: .Inlet)
    let inputW = NodePort<Float>(name: "W" , kind: .Inlet)

    let outputVector = NodePort<simd_float4>(name: "Vector 4" , kind: .Outlet)

    private var vector = simd_float4(repeating: 0)
    
    override var ports: [any AnyPort] { [inputX,
                                         inputY,
                                         inputZ,
                                         inputW,
                                         outputVector] }
    
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
        
        if let v = self.inputW.value {
            vector.w = v
        }
       
        self.outputVector.send( self.vector )
     }
}
