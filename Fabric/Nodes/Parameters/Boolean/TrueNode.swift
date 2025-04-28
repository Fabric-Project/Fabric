//
//  TrueNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/28/25.
//

import Foundation
import Satin
import simd
import Metal

class TrueNode : Node, NodeProtocol
{
    static let name = "True"
    static var nodeType = Node.NodeType.Parameter

    // Ports
    let outputBoolean = NodePort<Bool>(name: "True" , kind: .Outlet)

//    private let tween = Tween(duration: 10)
    
    override var ports: [any AnyPort] { [outputBoolean] }
        
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {

        self.outputBoolean.send( true )
     }
}
