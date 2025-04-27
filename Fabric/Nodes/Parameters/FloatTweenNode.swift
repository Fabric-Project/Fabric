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
    static var type = Node.NodeType.Parameter

    // Ports
    let inputDuration = NodePort<Float>(name: "Duration" , kind: .Inlet)
    let outputNumber = NodePort<Float>(name: FloatTweenNode.name , kind: .Outlet)

//    private let tween = Tween(duration: 10)
    
    override var ports: [any AnyPort] { [inputDuration, outputNumber] }
    
    required init(context:Context)
    {
        super.init(context: context, type: .Material, name: FloatTweenNode.name)
        
    }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
//        if let color = self.inputColor.value
//        {
//            self.material.color = color
//        }
//
//        self.material.color = simd_float4( cosf(Float( atTime.remainder(dividingBy: 1) )  * Float.pi ) , 0.0, 0.0, 1.0)

        let val = easeOutElastic( Float(( atTime / 10.0 ) .remainder(dividingBy: 1)) )
        print(val)
        self.outputNumber.send( val )
     }
}
