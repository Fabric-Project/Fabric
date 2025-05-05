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
         
         LoadTextureNode.self,
         HDRTextureNode.self,
         
         PlaneGeometryNode.self,
         BoxGeometryNode.self,
         SkyboxGeometryNode.self,
         SuperShapeGeometryNode.self,
         
         BasicColorMaterialNode.self,
         BasicTextureMaterialNode.self,
         BasicDiffuseMaterialNode.self,
         SkyboxMaterialNode.self,
         DepthMaterialNode.self,
         ShadowMaterialNode.self,
         StandardMaterialNode.self,
         
         DirectionalLightNode.self,
         
         MeshNode.self,
         SceneBuilderNode.self,
         RenderNode.self,
         
         TrueNode.self,
         FalseNode.self ,
         
         CurrentTimeNode.self,
         NumberNode.self,
         NumberAddNode.self,
         NumberSubtractNode.self ,
         NumberMultiplyNode.self,
         NumberDivideNode.self ,
         NumberModuloNode.self,
         NumberEaseNode.self,


         MakeVector2Node.self,
         MakeVector3Node.self,
         MakeVector4Node.self,
         
         MakeQuaternionNode.self
    ]
}
