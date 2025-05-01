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
    let outputNumber = NodePort<Float>(name: FloatTweenNode.name , kind: .Outlet)
    override var ports: [any AnyPort] { super.ports + [ outputNumber] }

    // Params
    let inputDurationParam = FloatParameter("Duration", 10.0, 0.1, 60.0, .slider)
    
    override var inputParameters:[any Parameter]  { [inputDurationParam] }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        
        let duration = Double(self.inputDurationParam.value)

        let loopedTime = atTime.truncatingRemainder(dividingBy: duration)

        let easeTime = loopedTime / duration
        
        let val = easeOutElastic( easeTime)
        
        self.outputNumber.send( Float(val) )
     }
}
