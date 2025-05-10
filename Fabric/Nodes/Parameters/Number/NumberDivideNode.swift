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

class NumberDivideNode : Node, NodeProtocol
{
    static let name = "Number Divide"
    static var nodeType = Node.NodeType.Parameter

    // Ports
    let outputNumber = NodePort<Float>(name: NumberDivideNode.name , kind: .Outlet)
   
    override var ports: [any AnyPort] { super.ports + [ outputNumber] }

    // Params
    let inputAParam = FloatParameter("A", 0.0, .inputfield)
    let inputBParam = FloatParameter("B", 0.0, .inputfield)

    override var inputParameters:[any Parameter]  { [inputAParam, inputBParam] }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        
       
        self.outputNumber.send(self.inputAParam.value / self.inputBParam.value )
     }
}
