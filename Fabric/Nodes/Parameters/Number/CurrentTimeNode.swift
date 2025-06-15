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
    static var nodeType = Node.NodeType.Parameter(parameterType: .Number)

    override var isDirty:Bool { get {  true  } set { } }

    private let startTime = Date.timeIntervalSinceReferenceDate
    
    // Ports
    let outputNumber:NodePort<Float>
    override var ports: [any NodePortProtocol] { super.ports + [ outputNumber] }
    
    required init(context: Context)
    {
        self.outputNumber =  NodePort<Float>(name: CurrentTimeNode.name , kind: .Outlet)

        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case outputNumberPort
    }
    
    override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.outputNumber, forKey: .outputNumberPort)
        
        try super.encode(to: encoder)
    }
    
    required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.outputNumber = try container.decode(NodePort<Float>.self, forKey: .outputNumberPort)
        
        try super.init(from: decoder)
    }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        self.outputNumber.send( Float(atTime - startTime) )
    }
}
