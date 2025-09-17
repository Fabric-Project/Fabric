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
        // Cameras
         PerspectiveCameraNode.self,
         OrthographicCameraNode.self,
         
         // Texture
         LoadTextureNode.self,
         HDRTextureNode.self,
         BrightnessContrastImageNode.self,
         GaussianBlurImageNode.self,
         
         // Geometry
         PlaneGeometryNode.self,
         PointPlaneGeometryNode.self,
         BoxGeometryNode.self,
         SphereGeometryNode.self,
         IcoSphereGeometryNode.self,
         CapsuleGeometryNode.self,
         SkyboxGeometryNode.self,
         ExtrudedTextGeometryNode.self,
         SuperShapeGeometryNode.self,
         
         // Materials
         BasicColorMaterialNode.self,
         BasicTextureMaterialNode.self,
         BasicDiffuseMaterialNode.self,
         SkyboxMaterialNode.self,
         DepthMaterialNode.self,
         //ShadowMaterialNode.self,
         StandardMaterialNode.self,
         PBRMaterialNode.self,
         DisplacementMaterialNode.self,

         // Lights
         DirectionalLightNode.self,
         
         // Objects / Rendering
         MeshNode.self,
         ModelMeshNode.self,
         SceneBuilderNode.self,
         RenderNode.self,
         DeferredRenderNode.self,
         
         // Boolean
         TrueNode.self,
         FalseNode.self,
         ArrayIndexValueNode<Bool>.self,
         ArrayCountNode<Bool>.self,

         // Number
         CurrentTimeNode.self,
         NumberNode.self,
         NumberUnnaryOperator.self,
         NumberBinaryOperator.self,
         NumberEaseNode.self,
         NumberRemapNode.self,
         NumberIntegralNode.self,
         GradientNoiseNode.self,
         ArrayIndexValueNode<Float>.self,
         ArrayCountNode<Float>.self,

         // String
         TextFileLoaderNode.self,
         StringComponentNode.self,
         StringLengthNode.self,
         StringRangeNode.self,
         ArrayIndexValueNode<String>.self,
         ArrayCountNode<String>.self,
         
         // Vectors
         MakeVector2Node.self,
         MakeVector3Node.self,
         MakeVector4Node.self,
         
//         MakeQuaternionNode.self
    ]
}
