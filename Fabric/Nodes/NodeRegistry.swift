//
//  NodeRegistry.swift
//  Fabric
//
//  Created by Anton Marini on 4/26/25.
//
import simd

public class NodeRegistry {
    
    public static let shared = NodeRegistry()
    
    
    public func nodeClass(for nodeName: String) -> (any NodeProtocol.Type)? {
        return self.nodesClassLookup[nodeName]
    }
    
    public var availableNodes:[NodeClassWrapper] {
        self.nodesClasses.map( { NodeClassWrapper(nodeClass: $0) } ) + self.dynamicEffectNodes
    }

    private var nodesClassLookup: [String: any NodeProtocol.Type] {
        self.nodesClasses.reduce(into: [:]) { result, nodeClass in
            result[String(describing: nodeClass)] = nodeClass
        }
    }
    
    private var nodesClasses: [any NodeProtocol.Type] {
        self.cameraNodeClasses
        + self.lightNodeClasses
        + self.objectNodeClasses
        + self.geometryNodeClasses
        + self.materialNodeClasses
        + self.textureNodeClasses
        + self.parameterNodeClasses }
    
    private var cameraNodeClasses: [any NodeProtocol.Type] = [
         PerspectiveCameraNode.self,
         OrthographicCameraNode.self,
    ]
    
    private var lightNodeClasses: [any NodeProtocol.Type] = [
        DirectionalLightNode.self,
        PointLightNode.self,
    ]
    
    private var objectNodeClasses: [any NodeProtocol.Type] = [
        // Objects / Rendering
        MeshNode.self,
        ModelMeshNode.self,
        InstancedMeshNode.self,
        SceneBuilderNode.self,
        RenderNode.self,
        DeferredRenderNode.self
    ]
    
    private var geometryNodeClasses: [any NodeProtocol.Type] = [ // Geometry
        PlaneGeometryNode.self,
        PointPlaneGeometryNode.self,
        BoxGeometryNode.self,
        SphereGeometryNode.self,
        IcoSphereGeometryNode.self,
        CapsuleGeometryNode.self,
        SkyboxGeometryNode.self,
        TesselatedTextGeometryNode.self,
        ExtrudedTextGeometryNode.self,
        SuperShapeGeometryNode.self
    ]
        
    private var materialNodeClasses:[any NodeProtocol.Type] = [
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
    ]
    
    private var textureNodeClasses:[any NodeProtocol.Type] = [
        LoadTextureNode.self,
        HDRTextureNode.self,
//        BrightnessContrastImageNode.self,
//        GaussianBlurImageNode.self,
    ]
    
    private var dynamicEffectNodes:[NodeClassWrapper] {
        let bundle = Bundle(for: Self.self)

        var nodes:[NodeClassWrapper] = []

        for imageEffectType in Node.NodeType.ImageType.allCases
        {
            let subDir = "Effects/\(imageEffectType.rawValue)"
            
            if var shaderURLs = bundle.urls(forResourcesWithExtension: "metal", subdirectory:subDir)
            {
                // Not quite a localizedStandardCompare but whatever
                shaderURLs.sort { a, b in
                    
                    return self.fileURLToName(fileURL: a) < self.fileURLToName(fileURL: b)
                }
                
                for fileURL in shaderURLs
                {
                    let node = NodeClassWrapper(nodeClass: BaseEffectNode.self,
                                                nodeType: .Image(imageType: imageEffectType),
                                                fileURL: fileURL,
                                                nodeName:self.fileURLToName(fileURL: fileURL))
                    nodes.append( node )
                }
            }
        }
        
        return nodes
    }
    
    private func fileURLToName(fileURL:URL) -> String {
        let nodeName =  fileURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "ImageNode", with: "")

        return nodeName.titleCase
    }
    
    private var parameterNodeClasses: [any NodeProtocol.Type] = [
        // Boolean
        TrueNode.self,
        FalseNode.self,
        ArrayIndexValueNode<Bool>.self,
        ArrayCountNode<Bool>.self,
        ArrayQueueNode<Bool>.self,

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
        ArrayQueueNode<Float>.self,

        // String
        TextFileLoaderNode.self,
        StringComponentNode.self,
        StringLengthNode.self,
        StringRangeNode.self,
        ArrayIndexValueNode<String>.self,
        ArrayCountNode<String>.self,
        ArrayQueueNode<String>.self,

        // Vectors
        MakeVector2Node.self,
        ArrayIndexValueNode<simd_float2>.self,
        ArrayCountNode<simd_float2>.self,
        ArrayQueueNode<simd_float2>.self,
        
        MakeVector3Node.self,
        ArrayIndexValueNode<simd_float3>.self,
        ArrayCountNode<simd_float3>.self,
        ArrayQueueNode<simd_float3>.self,
        
        MakeVector4Node.self,
        ArrayIndexValueNode<simd_float4>.self,
        ArrayCountNode<simd_float4>.self,
        ArrayQueueNode<simd_float4>.self,

        ]
}
