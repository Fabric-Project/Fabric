//
//  FloatTween.swift
//  Fabric
//
//  Created by Anton Marini on 4/26/25.
//


import Foundation
import Satin
import simd
import Metal

class FloatTweenNode : Node, NodeProtocol
{
    static let name = "Number Tween"
    static var nodeType = Node.NodeType.Parameter

    // Ports
    let inputDuration = NodePort<Float>(name: "Duration" , kind: .Inlet)
    let outputNumber = NodePort<Float>(name: FloatTweenNode.name , kind: .Outlet)
    
    override var ports: [any AnyPort] { [inputDuration, outputNumber] }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {

        let val = easeOutElastic( Float(( atTime / 10.0 ) .truncatingRemainder(dividingBy: 1)) )

        self.outputNumber.send( val )
     }
}
