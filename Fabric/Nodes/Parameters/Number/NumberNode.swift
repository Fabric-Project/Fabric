//
//  FloatAddNode.swift
//  Fabric
//
//  Created by Anton Marini on 5/2/25.
//

import Foundation


import Foundation
import Satin
import simd
import Metal

class NumberNode : Node, NodeProtocol
{
    static let name = "Number"
    static var nodeType = Node.NodeType.Parameter

    // Ports
    let outputNumber = NodePort<Float>(name: NumberAddNode.name , kind: .Outlet)
   
    override var ports: [any AnyPort] { super.ports + [ outputNumber] }

    // Params
    let inputNumberParam = GenericParameter<Float>("Number", 0.0, .inputfield)

    override var inputParameters:[any Parameter]  { [inputNumberParam] }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        self.outputNumber.send(self.inputNumberParam.value)
    }
}
