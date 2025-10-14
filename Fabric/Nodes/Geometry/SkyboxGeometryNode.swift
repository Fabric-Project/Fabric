//
//  SkyboxGeometryNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//

import Satin
import Foundation
import simd
import Metal

public class SkyboxGeometryNode : Node
{
    override public class var name:String { "Skybox Geometry" }
    override public class var nodeType:Node.NodeType { Node.NodeType.Geometery }

    // Ports
    
    public let outputGeometry:NodePort<Geometry>
    
    public override var ports:[AnyPort] {  [outputGeometry] + super.ports}

    private let geometry = SkyboxGeometry(size: 50)

    public required init(context:Context)
    {
        self.outputGeometry = NodePort<Geometry>(name: SkyboxGeometryNode.name, kind: .Outlet)
        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case outputGeometryPort
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.outputGeometry = try container.decode(NodePort<Geometry>.self, forKey: .outputGeometryPort)
        try super.init(from: decoder)
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.outputGeometry, forKey: .outputGeometryPort)
        try super.encode(to: encoder)
    }

    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
            
        self.outputGeometry.send(self.geometry)
     }
}
