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

class CurrentTimeNode : Node, NodeProtocol
{
    static let name = "Current Time"
    static var nodeType = Node.NodeType.Parameter
    
    private let startTime = Date.timeIntervalSinceReferenceDate
    
    // Ports
    let outputNumber = NodePort<Float>(name: CurrentTimeNode.name , kind: .Outlet)
    
    override var ports: [any AnyPort] { super.ports + [ outputNumber] }
    
    override var inputParameters:[any Parameter]  { [] }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        self.outputNumber.send( Float(atTime - startTime) )
    }
}
