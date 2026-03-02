//
//  NodeRegistry.swift
//  Fabric
//
//  Created by Anton Marini on 4/26/25.
//
import simd
import Foundation

public class NodeRegistry {
    
    public static let shared = NodeRegistry()
    
    
    public func nodeClass(for nodeName: String) -> (Node.Type)? {
        return self.nodesClassLookup[nodeName]
    }
    
    public lazy private(set) var availableNodes:[NodeClassWrapper] = {
        self.nodesClasses.map( { NodeClassWrapper(nodeClass: $0) } ) + self.dynamicEffectNodes
    }()

    private lazy var nodesClassLookup: [String: Node.Type] =  {
        self.nodesClasses.reduce(into: [:]) { result, nodeClass in
            result[String(describing: nodeClass)] = nodeClass
        }
    }()
    
    private var nodesClasses: [Node.Type] {
        self.cameraNodeClasses
        + self.lightNodeClasses
        + self.objectNodeClasses
        + self.geometryNodeClasses
        + self.materialNodeClasses
        + self.textureNodeClasses
        + self.parameterNodeClasses
        + self.ioNodeClasses
        + self.macroNodeClasses
        + self.utilityClasses
    }
    
    private var cameraNodeClasses: [Node.Type] = [
         PerspectiveCameraNode.self,
         OrthographicCameraNode.self,
    ]
    
    private var lightNodeClasses: [Node.Type] = [
        DirectionalLightNode.self,
        PointLightNode.self,
    ]
    
    private var objectNodeClasses: [Node.Type] = [
        // Objects / Rendering
        MeshNode.self,
        ModelMeshNode.self,
        InstancedMeshNode.self,
        InstancedModelMeshNode.self,
        EnvironmentSkyboxNode.self,
        BillboardNode.self,
    ]
    
    private var geometryNodeClasses: [Node.Type] = [ // Geometry
        PlaneGeometryNode.self,
        PerspectiveQuadGeometryNode.self,
        RoundRectGeometryNode.self,
        TriangleGeometryNode.self,
        CircleGeometryNode.self,
        ArcGeometryNode.self,
        ConeGeometryNode.self,
        BoxGeometryNode.self,
        RoundBoxGeometryNode.self,
        SphereGeometryNode.self,
        IcoSphereGeometryNode.self,
        CapsuleGeometryNode.self,
        TubeGeometryNode.self,
        TorusGeometryNode.self,
//        SkyboxGeometryNode.self,
        TesselatedTextGeometryNode.self,
        ExtrudedTextGeometryNode.self,
        PixelArrayToGeometryNode.self,
        SuperShapeGeometryNode.self,
    ]
        
    private var materialNodeClasses:[Node.Type] = [
        // Materials
        BasicColorMaterialNode.self,
        UVMaterialNode.self,
        BasicTextureMaterialNode.self,
        BasicDiffuseMaterialNode.self,
//        SkyboxMaterialNode.self,
        DepthMaterialNode.self,
        //ShadowMaterialNode.self,
        StandardMaterialNode.self,
        PBRMaterialNode.self,
        DisplacementMaterialNode.self,
    ]
    
    private var textureNodeClasses:[Node.Type] {
        var classes: [Node.Type] = [
            MovieProviderNode.self,
            CameraProviderNode.self,
            ImageProviderNode.self,
            TestCardProviderNode.self,
        ]
        #if os(macOS)
        classes.append(ScreenCaptureProviderNode.self)
        #endif
        #if FABRIC_SYPHON_ENABLED
        classes.append(contentsOf: [
            SyphonClientNode.self,
            SyphonServerNode.self,
        ])
        #endif
        classes.append(contentsOf: [
            GaussianBlurNode.self,
            MotionBlurNode.self,
            ZoomBlurNode.self,
            ForegroundMaskNode.self,
            PersonSegmentationMaskNode.self,
            FacePoseAnalysisNode.self,
            HandPoseAnalysisNode.self,
            LocalVLMNode.self,
            ContourPathNode.self,
            MetalFXSpatialUpsample2xNode.self,
            KeypointDistortNode.self,
            LUTProcessorNode.self,

            ArrayIndexValueNode<FabricImage>.self,
            ArrayCountNode<FabricImage>.self,
            ArrayQueueNode<FabricImage>.self,
            ArrayReplaceValueAtIndexNode<FabricImage>.self,
        ])
        return classes
    }

    // Sub Patch Iterator, Replicate etc
    private var macroNodeClasses:[Node.Type] = [
        SubgraphNode.self,
        DeferredSubgraphNode.self,
        IteratorNode.self,
        IteratorInfoNode.self,
        EnvironmentNode.self,
    ]
    
    private var dynamicEffectNodes:[NodeClassWrapper]
    {
        let bundle = Bundle.module

        var nodes:[NodeClassWrapper] = []

        for imageEffectType in Node.NodeType.ImageType.allCases
        {
            let singleChannelEffects = "Effects/\(imageEffectType.rawValue)"
            let twoChannelEffects = "EffectsTwoChannel/\(imageEffectType.rawValue)"
            let threeChannelEffects = "EffectsThreeChannel/\(imageEffectType.rawValue)"
            
            let computeSubdir = "Compute/\(imageEffectType.rawValue)"
            
            if
               let singleChannelEffects = bundle.urls(forResourcesWithExtension: "metal", subdirectory:singleChannelEffects),
               let twoChannelEffects = bundle.urls(forResourcesWithExtension: "metal", subdirectory:twoChannelEffects),
               let threeChannelEffects = bundle.urls(forResourcesWithExtension: "metal", subdirectory:threeChannelEffects),
               let singleChannelComputeEffects = bundle.urls(forResourcesWithExtension: "metal", subdirectory:computeSubdir)
            {
                for fileURL in singleChannelEffects
                {
                    let baseClass = [.Generator, .ShapeGenerator].contains(imageEffectType) ? BaseGeneratorNode.self : BaseEffectNode.self
                    let node = NodeClassWrapper(nodeClass: baseClass,
                                                nodeType: .Image(imageType: imageEffectType),
                                                fileURL: fileURL,
                                                nodeName:self.fileURLToName(fileURL: fileURL))
                    nodes.append( node )
                }
                
                for fileURL in twoChannelEffects
                {
                    let node = NodeClassWrapper(nodeClass: BaseEffectTwoChannelNode.self,
                                                nodeType: .Image(imageType: imageEffectType),
                                                fileURL: fileURL,
                                                nodeName:self.fileURLToName(fileURL: fileURL))
                    nodes.append( node )
                }

                for fileURL in threeChannelEffects
                {
                    let node = NodeClassWrapper(nodeClass: BaseEffectThreeChannelNode.self,
                                                nodeType: .Image(imageType: imageEffectType),
                                                fileURL: fileURL,
                                                nodeName:self.fileURLToName(fileURL: fileURL))
                    nodes.append( node )
                }
                
                for fileURL in singleChannelComputeEffects
                {
                    let node = NodeClassWrapper(nodeClass: BaseTextureComputeProcessorNode.self,
                                                nodeType: .Image(imageType: imageEffectType),
                                                fileURL: fileURL,
                                                nodeName:self.fileURLToName(fileURL: fileURL))
                    nodes.append( node )
                }
            }
        }
        
        // Not quite a localizedStandardCompare but whatever
        nodes.sort { a, b in
            
            return a.nodeName < b.nodeName
        }
        return nodes
    }
    
    private func fileURLToName(fileURL:URL) -> String {
        let nodeName =  fileURL.deletingPathExtension().lastPathComponent.replacing("ImageNode", with: "")

        return nodeName.titleCase
    }
    
    private var parameterNodeClasses: [Node.Type] = [
        // Boolean
        TrueNode.self,
        FalseNode.self,
        BooleanLogicNode.self,
        ArrayFirstValueNode<Bool>.self,
        ArrayLastValueNode<Bool>.self,
        ArrayIndexValueNode<Bool>.self,
        ArrayCountNode<Bool>.self,
        ArrayQueueNode<Bool>.self,
        ArrayReplaceValueAtIndexNode<Bool>.self,

        // Number
        CurrentTimeNode.self,
        SystemTimeNode.self,
        NumberNode.self,
        TimelineNode.self,
        NumberUnaryOperator.self,
        NumberBinaryOperator.self,
        NumberLogicOperator.self,
        NumberRoundNode.self,
        NumberClampNode.self,
        NumberEaseNode.self,
        NumberRemapNode.self,
        NumberIntegralNode.self,
        NumberSmoothNode.self,
        MathExpressionNode.self,
        GradientNoiseNode.self,
        AudioSpectrumNode.self,
        ArrayFirstValueNode<Float>.self,
        ArrayLastValueNode<Float>.self,
        ArrayIndexValueNode<Float>.self,
        ArrayCountNode<Float>.self,
        ArrayQueueNode<Float>.self,
        ArrayReplaceValueAtIndexNode<Float>.self,
        FloatArrayToVector2ArrayNode.self,
        FloatArrayToVector3ArrayNode.self,
        Vector2ArrayToVector3ArrayNode.self,
        Vector3ArrayToTransformArrayNode.self,
        
        // String
        StringNode.self,
        TextFileLoaderNode.self,
        StringJoinNode.self,
        StringComponentNode.self,
        StringLengthNode.self,
        StringRangeNode.self,
        StringWrapNode.self,
        StringRemoveWhitespaceNode.self,
        StringDifferenceNode.self,
//        ConvertToStringNode.self,
        LocalLLMNode.self,
        ArrayFirstValueNode<String>.self,
        ArrayLastValueNode<String>.self,
        ArrayIndexValueNode<String>.self,
        ArrayCountNode<String>.self,
        ArrayQueueNode<String>.self,
        ArrayReplaceValueAtIndexNode<String>.self,

        // Vectors
        MakeVector2Node.self,
        Vector2ToFloatNode.self,
        Vector2Distance.self,
        ArrayFirstValueNode<simd_float2>.self,
        ArrayLastValueNode<simd_float2>.self,
        ArrayIndexValueNode<simd_float2>.self,
        ArrayCountNode<simd_float2>.self,
        ArrayQueueNode<simd_float2>.self,
        ArrayReplaceValueAtIndexNode<simd_float2>.self,
        PolyLineSimplifyNode.self,
        
        MakeVector3Node.self,
        Vector3ToFloatNode.self,
        Vector3Distance.self,
        ArrayFirstValueNode<simd_float3>.self,
        ArrayLastValueNode<simd_float3>.self,
        ArrayIndexValueNode<simd_float3>.self,
        ArrayCountNode<simd_float3>.self,
        ArrayQueueNode<simd_float3>.self,
        ArrayReplaceValueAtIndexNode<simd_float3>.self,

        MakeVector4Node.self,
        Vector4ToFloatNode.self,
        Vector4Distance.self,
        ArrayFirstValueNode<simd_float4>.self,
        ArrayLastValueNode<simd_float4>.self,
        ArrayIndexValueNode<simd_float4>.self,
        ArrayCountNode<simd_float4>.self,
        ArrayQueueNode<simd_float4>.self,
        ArrayReplaceValueAtIndexNode<simd_float4>.self,

        // Quaternion
        MakeQuaternionNode.self,
        
        // Transform (Float Matrix 4x4)
        IdentityTransformNode.self,
        RotateTransformNode.self,
        ScaleTransformNode.self,
        TranslateTransformNode.self,
        TransposeTransformNode.self,
        InvertTransformNode.self,
        DecomposeTransformNode.self,
        GeometryToTransformArrayNode.self,
        ArrayFirstValueNode<simd_float4x4>.self,
        ArrayLastValueNode<simd_float4x4>.self,
        ArrayIndexValueNode<simd_float4x4>.self,
        ArrayCountNode<simd_float4x4>.self,
        ArrayQueueNode<simd_float4x4>.self,
        ArrayReplaceValueAtIndexNode<simd_float4x4>.self,

        ]
    
    private var ioNodeClasses: [Node.Type] {
        var classes: [Node.Type] = [
            OSCReceiveNode.self,
        ]
        #if os(macOS)
        classes.append(HIDNode.self)
        #endif
        classes.append(contentsOf: [
            GameControllerNode.self,
            MIDIInputNode.self,
        ])
        return classes
    }

    private var utilityClasses: [Node.Type] {
        var classes: [Node.Type] = [
            LogNode.self,
            CursorNode.self,
        ]
        #if os(macOS)
        classes.append(KeyboardNode.self)
        #endif
        classes.append(contentsOf: [
            RenderInfoNode.self,
            ImageDimensions.self,
            PixelsToUnitsNode.self,
            UnitsoPixelsNode.self,

            SignalNode.self,

            SampleAndHoldNode<Bool>.self,
            SampleAndHoldNode<Float>.self,
            SampleAndHoldNode<simd_float2>.self,
            SampleAndHoldNode<simd_float3>.self,
            SampleAndHoldNode<simd_float4>.self,
            SampleAndHoldNode<String>.self,
            SampleAndHoldNode<simd_quatf>.self,
            SampleAndHoldNode<simd_float4x4>.self,
            SampleAndHoldNode<FabricImage>.self,

            SampleAndHoldNode<ContiguousArray<Bool>>.self,
            SampleAndHoldNode<ContiguousArray<Float>>.self,
            SampleAndHoldNode<ContiguousArray<simd_float2>>.self,
            SampleAndHoldNode<ContiguousArray<simd_float3>>.self,
            SampleAndHoldNode<ContiguousArray<simd_float4>>.self,
            SampleAndHoldNode<ContiguousArray<String>>.self,
        ])
        return classes
    }
}
