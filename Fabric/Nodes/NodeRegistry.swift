//
//  NodeRegistry.swift
//  Fabric
//
//  Created by Anton Marini on 4/26/25.
//

class NodeRegistry {
    
    static let shared = NodeRegistry()
    
    var nodesClassLookup: [String: any NodeProtocol.Type] {
        self.nodesClasses.reduce(into: [:]) { result, nodeClass in
            result[String(describing: nodeClass)] = nodeClass
        }
    }
    
    func nodeClass(for nodeName: String) -> (any NodeProtocol.Type)? {
        return self.nodesClassLookup[nodeName]
    }
    
    let nodesClasses: [any NodeProtocol.Type] = [
         PerspectiveCameraNode.self,
         
         LoadTextureNode.self,
         HDRTextureNode.self,
         BasicColorTextureNode.self,
         
         PlaneGeometryNode.self,
         BoxGeometryNode.self,
         SphereGeometryNode.self,
         IcoSphereGeometryNode.self,
         SkyboxGeometryNode.self,
         SuperShapeGeometryNode.self,
         
         BasicColorMaterialNode.self,
         BasicTextureMaterialNode.self,
         BasicDiffuseMaterialNode.self,
         SkyboxMaterialNode.self,
         DepthMaterialNode.self,
         //ShadowMaterialNode.self,
         StandardMaterialNode.self,
         PBRMaterialNode.self,
         
         DirectionalLightNode.self,
         
         MeshNode.self,
         ModelMeshNode.self,
         SceneBuilderNode.self,
         RenderNode.self,
         DeferredRenderNode.self,
         
         TrueNode.self,
         FalseNode.self ,
         
         CurrentTimeNode.self,
         NumberNode.self,
         NumberUnnaryOperator.self,
         NumberBinaryOperator.self,
         
//         NumberAddNode.self,
//         NumberSubtractNode.self ,
//         NumberMultiplyNode.self,
//         NumberDivideNode.self ,
//         NumberModuloNode.self,
         
         NumberEaseNode.self,
         NumberRemapNode.self,
         NumberIntegralNode.self,
         GradientNoiseNode.self,
         
         MakeVector2Node.self,
         MakeVector3Node.self,
         MakeVector4Node.self,
         
//         MakeQuaternionNode.self
    ]
}
