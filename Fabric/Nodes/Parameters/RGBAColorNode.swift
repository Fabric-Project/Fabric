//
//  ColorNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//

import Foundation
import Satin
import simd
import Metal

class RGBAColorNode : Node, NodeProtocol
{
    static let name = "RGBA Color"
    static var type = Node.NodeType.Parameter

    // Ports
    let inputRed = NodePort<Float>(name: "Red" , kind: .Inlet)
    let inputGreen = NodePort<Float>(name: "Green" , kind: .Inlet)
    let inputBlue = NodePort<Float>(name: "Blue" , kind: .Inlet)
    let inputAlpha = NodePort<Float>(name: "Alpha" , kind: .Inlet)

    let outputColor = NodePort<simd_float4>(name: RGBAColorNode.name , kind: .Outlet)

    private var color = simd_float4(repeating: 1)
    
    override var ports: [any AnyPort] { [inputRed,
                                         inputGreen,
                                         inputBlue,
                                         inputAlpha,
                                         outputColor] }
    
    required init(context:Context)
    {
        super.init(context: context, type: .Material, name: RGBAColorNode.name)
        
    }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        if let v = self.inputRed.value {
            color.x = v
        }
        
        if let v = self.inputGreen.value {
            color.y = v
        }
        
        if let v = self.inputBlue.value {
            color.z = v
        }
        
        if let v = self.inputAlpha.value {
            color.w = v
        }
        

        self.outputColor.send( self.color )
     }
}
