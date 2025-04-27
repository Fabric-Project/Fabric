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

class SkyboxGeometryNode : Node, NodeProtocol
{
    static let name = "Skybox Geometry"
    static var type = Node.NodeType.Geometery

    // Ports
    
    let outputGeometry = NodePort<Geometry>(name: SkyboxGeometryNode.name, kind: .Outlet)

    private let geometry = SkyboxGeometry(size: 50)
    
    override var ports:[any AnyPort] { [outputGeometry] }

    required init(context:Context)
    {
        super.init(context: context, type: .Geometery, name: SkyboxGeometryNode.name)
        
        self.geometry.setup()
    }
    
    override func evaluate(atTime:TimeInterval,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
            
        self.outputGeometry.send(self.geometry)
     }
}
