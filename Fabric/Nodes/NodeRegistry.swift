//
//  NodeRegistry.swift
//  Fabric
//
//  Created by Anton Marini on 4/26/25.
//

class NodeRegistry {
    
    static let shared = NodeRegistry()
    
    let nodesClasses: [any NodeProtocol.Type] = [
         PerspectiveCameraNode.self,
         BoxGeometryNode.self,
         BasicColorMaterialNode.self,
         DepthMaterialNode.self,
         MeshNode.self,
         RenderNode.self,
         
         FloatTweenNode.self,
         RGBAColorNode.self
    ]
}
