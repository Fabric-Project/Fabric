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

class NumberSubtractNode : Node, NodeProtocol
{
    static let name = "Number Subtract"
    static var nodeType = Node.NodeType.Parameter

    // Ports
    let outputNumber = NodePort<Float>(name: NumberSubtractNode.name , kind: .Outlet)
   
    override var ports: [any AnyPort] { super.ports + [ outputNumber] }

    // Params
    let inputAParam = GenericParameter<Float>("A", 0.0, .inputfield)
    let inputBParam = GenericParameter<Float>("B", 0.0, .inputfield)

    override var inputParameters:[any Parameter]  { super.inputParameters + [inputAParam, inputBParam] }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        
       
        self.outputNumber.send(self.inputAParam.value - self.inputBParam.value )
     }
}
