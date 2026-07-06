//
//  NodeRegistry.swift
//  Fabric
//
//  Created by Anton Marini on 4/26/25.
//
import simd
import Foundation
import Satin
import UniformTypeIdentifiers

public class NodeRegistry {
    
    public static let shared = NodeRegistry()
    
    public func nodeClass(for nodeName: String) -> (Node.Type)? {
        return self.nodesClassLookup[nodeName]
    }

    /// Returns the first drop-target node class whose `supportedContentTypes`
    /// conforms to the given UTType. More specific types (e.g. .jpeg) are
    /// checked via `UTType.conforms(to:)`, so dropping a JPEG will match
    /// `ImageProviderNode` whose list includes `.image`.
    public func dropTargetNodeClass(for contentType: UTType) -> (any NodeFileLoadingProtocol.Type)?
    {
        for dropNodeClass in self.nodeFileLoadingClasses
        {
            if dropNodeClass.supportedContentTypes.contains(where: { contentType.conforms(to: $0) } )
            {
                return dropNodeClass
            }
        }
        return nil
    }
    
    /// All UTTypes accepted by drop-target nodes, for use with drop destination handlers.
    public lazy private(set) var allSupportedDropTypes: [UTType] = {
        let dropClasses = self.nodeFileLoadingClasses
        return dropClasses.flatMap ( { $0.supportedContentTypes } )
    }()
    
    
    public lazy private(set) var availableNodes:[NodeClassWrapper] = {
        self.nodesClasses.map( { NodeClassWrapper(nodeClass: $0) } ) + self.dynamicEffectNodes
    }()

    private lazy var nodesClassLookup: [String: Node.Type] =  {
        var result = self.nodesClasses.reduce(into: [String: Node.Type]()) { result, nodeClass in
            result[String(describing: nodeClass)] = nodeClass
        }
        // Legacy class-name aliases: old saved graphs used SatinGeometry in generic type params.
        // Both module-qualified and bare forms are covered since Swift's output can vary.
        result["PassThroughNode<SatinGeometry>"] = PassThroughNode<Geometry>.self
        result["PassThroughNode<Satin.SatinGeometry>"] = PassThroughNode<Geometry>.self

        // Structural array nodes were previously generic; old docs decode to type-agnostic versions.
        let agnosticSuffixes = ["Bool", "Int", "Float", "String",
                                "simd_float2", "simd_float3", "simd_float4", "simd_float4x4",
                                "FabricImage"]
        for suffix in agnosticSuffixes {
            result["ArrayQueueNode<\(suffix)>"]               = ArrayQueueNode.self
            result["ArrayFirstValueNode<\(suffix)>"]          = ArrayFirstValueNode.self
            result["ArrayLastValueNode<\(suffix)>"]           = ArrayLastValueNode.self
            result["ArrayIndexValueNode<\(suffix)>"]          = ArrayIndexValueNode.self
            result["ArrayCountNode<\(suffix)>"]               = ArrayCountNode.self
            result["ArrayAppendNode<\(suffix)>"]              = ArrayAppendNode.self
            result["ArrayReplaceValueAtIndexNode<\(suffix)>"] = ArrayReplaceValueAtIndexNode.self
            result["ArraySplitAtIndexNode<\(suffix)>"]        = ArraySplitAtIndexNode.self
        }

        // Vector compose/decompose nodes were previously generic; old docs map to consolidated versions.
        let vectorSuffixes = ["simd_float2", "simd_float3", "simd_float4"]
        for suffix in vectorSuffixes {
            result["ComposeVectorNode<\(suffix)>"]       = ComposeVectorNode.self
            result["DecomposeVectorNode<\(suffix)>"]     = DecomposeVectorNode.self
            result["ComposeVectorArrayNode<\(suffix)>"]  = ComposeVectorArrayNode.self
            result["DecomposeVectorArrayNode<\(suffix)>"] = DecomposeVectorArrayNode.self
        }

        return result
    }()
    
    private lazy var nodeFileLoadingClasses: [(any NodeFileLoadingProtocol.Type)] =  {
        self.nodesClasses.compactMap( { $0 as? any NodeFileLoadingProtocol.Type } )
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
        SpotLightNode.self,
    ]
    
    private var objectNodeClasses: [Node.Type] = [
        // Objects / Rendering
        MeshNode.self,
        ModelMeshNode.self,
        InstancedMeshNode.self,
        InstancedModelMeshNode.self,
        EnvironmentSkyboxNode.self,
        ImageMeshNode.self,
    ]
    
    private var geometryNodeClasses: [Node.Type] = [ // Geometry
        PassThroughNode<Geometry>.self,
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
        CycloramaGeometryNode.self,
//        SkyboxGeometryNode.self,
        TesselatedTextGeometryNode.self,
        ExtrudedTextGeometryNode.self,
        PixelArrayToGeometryNode.self,
        SuperShapeGeometryNode.self,
        MobiusStripGeometryNode.self,
        HelicoidGeometryNode.self,
        SuperellipsoidGeometryNode.self,
        KleinBottleGeometryNode.self,
        CatenoidGeometryNode.self,
        ParaboloidGeometryNode.self,
        EnneperSurfaceGeometryNode.self,
        PseudosphereGeometryNode.self,
        DupinCyclideGeometryNode.self,
        RomanSurfaceGeometryNode.self,
        CrossCapGeometryNode.self,
        BourSurfaceGeometryNode.self,
        BreatherSurfaceGeometryNode.self,
        DiniSurfaceGeometryNode.self,
        MathExpressionParametricGeometryNode.self,
    ]
        
    private var materialNodeClasses:[Node.Type] = [
        // Materials
        PassThroughNode<Material>.self,
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
            PassThroughNode<FabricImage>.self,
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
            LiveImageNode.self,
            DepthOfFieldNode.self,
            GaussianBlurNode.self,
            MotionBlurNode.self,
            PostProcessMotionBlurNode.self,
            ZoomBlurNode.self,
            ForegroundMaskNode.self,
            PersonSegmentationMaskNode.self,
            FacePoseAnalysisNode.self,
            HandPoseAnalysisNode.self,
            LucasKanadeOpticalFlowNode.self,
            DCTNode.self,
            InverseDCTNode.self,
            LocalVLMNode.self,
            ContourPathNode.self,
            MetalFXSpatialUpsample2xNode.self,
            KeypointDistortNode.self,
            LUTProcessorNode.self,
            BlendNode.self,
            TextureCropNode.self,
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
                    let desc = self.shaderDescription(from: fileURL) ?? BaseImageNode.nodeDescription
                    let node = NodeClassWrapper(nodeClass: BaseImageNode.self,
                                                nodeType: .Image(imageType: imageEffectType),
                                                fileURL: fileURL,
                                                nodeName:self.fileURLToName(fileURL: fileURL),
                                                nodeDescription: desc)
                    nodes.append( node )
                }

                for fileURL in twoChannelEffects
                {
                    let desc = self.shaderDescription(from: fileURL) ?? BaseImageNode.nodeDescription
                    let node = NodeClassWrapper(nodeClass: BaseImageNode.self,
                                                nodeType: .Image(imageType: imageEffectType),
                                                fileURL: fileURL,
                                                nodeName:self.fileURLToName(fileURL: fileURL),
                                                nodeDescription: desc)
                    nodes.append( node )
                }

                for fileURL in threeChannelEffects
                {
                    let desc = self.shaderDescription(from: fileURL) ?? BaseImageNode.nodeDescription
                    let node = NodeClassWrapper(nodeClass: BaseImageNode.self,
                                                nodeType: .Image(imageType: imageEffectType),
                                                fileURL: fileURL,
                                                nodeName:self.fileURLToName(fileURL: fileURL),
                                                nodeDescription: desc)
                    nodes.append( node )
                }

                for fileURL in singleChannelComputeEffects
                {
                    let desc = self.shaderDescription(from: fileURL) ?? BaseTextureComputeProcessorNode.nodeDescription
                    let node = NodeClassWrapper(nodeClass: BaseTextureComputeProcessorNode.self,
                                                nodeType: .Image(imageType: imageEffectType),
                                                fileURL: fileURL,
                                                nodeName:self.fileURLToName(fileURL: fileURL),
                                                nodeDescription: desc)
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

    /// Parse a `// description: ...` comment from a shader file's first few lines.
    private func shaderDescription(from fileURL: URL) -> String? {
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
              let source = String(data: data, encoding: .utf8) else { return nil }
        // Scan only the first 20 lines for efficiency
        for line in source.split(separator: "\n", maxSplits: 20, omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("// description:") {
                let desc = trimmed.dropFirst("// description:".count).trimmingCharacters(in: .whitespaces)
                return desc.isEmpty ? nil : desc
            }
        }
        return nil
    }
    
    private var parameterNodeClasses: [Node.Type] = [
        // Boolean
        PassThroughNode<Bool>.self,
        BooleanLogicNode.self,
        RepeatValueNode<Bool>.self,

        // Index
        PassThroughNode<Int>.self,
        RepeatValueNode<Int>.self,
        
        // Number
        PassThroughNode<Float>.self,
        CurrentTimeNode.self,
        SystemTimeNode.self,
        TimestampNode.self,
        TimelineNode.self,
        NumberUnaryOperator.self,
        NumberBinaryOperator.self,
        NumberLogicOperator.self,
        NumberRoundNode.self,
        NumberClampNode.self,
        NumberEaseNode.self,
        NumberTweenNode.self,
        NumberRemapNode.self,
        NumberIntegralNode.self,
        NumberSmoothNode.self,
        MathExpressionNode.self,
        GradientNoiseNode.self,
        AudioSpectrumNode.self,
        ColorPassThroughNode.self,
        MakeColorNode.self,
        ColorTweenNode.self,
        OrientationTweenNode.self,
        ArrayMathExpressionNode.self,
        RepeatValueNode<Float>.self,
        ArrayFromRippledValueNode<Float>.self,
        ArrayResampleNode<Float>.self,
        ArrayRangeInterpolationNode<Float>.self,

        // String
        PassThroughNode<String>.self,
        StringTrimNode.self,
        StringLengthNode.self,
        StringRangeNode.self,
        StringWrapNode.self,
        StringCaseNode.self,
        StringFormatterNode.self,
        StringScannerNode.self,
        StringComparisonNode.self,
        StringJoinNode.self,
        StringDifferenceNode.self,
        StringSplitNode.self,
        TimestampFormatterNode.self,
        TimecodeFormatterNode.self,
//        ConvertToStringNode.self,
        LocalLLMNode.self,
        DirectoryScannerNode.self,
        TextFileLoaderNode.self,
        RepeatValueNode<String>.self,
        
        // Vectors
        // Consolidated non-generic compose/decompose nodes (type chosen in Settings).
        ComposeVectorNode.self,
        DecomposeVectorNode.self,
        ComposeVectorArrayNode.self,
        DecomposeVectorArrayNode.self,

        PassThroughNode<simd_float2>.self,
        VectorTweenNode<simd_float2>.self,
        Vector2Distance.self,
        RepeatValueNode<simd_float2>.self,
        ArrayFromRippledValueNode<simd_float2>.self,
        ArrayResampleNode<simd_float2>.self,
        ArrayRangeInterpolationNode<simd_float2>.self,
        VectorArrayTweenNode<simd_float2>.self,
        PolyLineSimplifyNode.self,

        PassThroughNode<simd_float3>.self,
        VectorTweenNode<simd_float3>.self,
        Vector3Distance.self,
        OrientationArrayTweenNode.self,
        ComposeTransformArrayNode.self,
        RepeatValueNode<simd_float3>.self,
        ArrayFromRippledValueNode<simd_float3>.self,
        ArrayResampleNode<simd_float3>.self,
        ArrayRangeInterpolationNode<simd_float3>.self,
        ComposeOrientationArrayNode.self,
        DecomposeOrientationArrayNode.self,
        VectorArrayTweenNode<simd_float3>.self,

        PassThroughNode<simd_float4>.self,
        VectorTweenNode<simd_float4>.self,
        Vector4Distance.self,
        RepeatValueNode<simd_float4>.self,
        ArrayFromRippledValueNode<simd_float4>.self,
        ArrayResampleNode<simd_float4>.self,
        ArrayRangeInterpolationNode<simd_float4>.self,
        VectorArrayTweenNode<simd_float4>.self,

        PassThroughNode<simd_quatf>.self,
        ComposeOrientationNode.self,
        DecomposeOrientationNode.self,

        // Transform (Float Matrix 4x4)
        PassThroughNode<simd_float4x4>.self,
        RotateTransformNode.self,
        ScaleTransformNode.self,
        TranslateTransformNode.self,
        TransposeTransformNode.self,
        InvertTransformNode.self,
        ComposeTransformNode.self,
        DecomposeTransformNode.self,
        GeometryToTransformArrayNode.self,
        RepeatValueNode<simd_float4x4>.self,
        DecomposeTransformArrayNode.self,

        // Type-agnostic array structure nodes (Virtual by default; type selected in Settings)
        // RepeatValueNode stays generic — the value inlet requires a typed default parameter port.
        ArrayFirstValueNode.self,
        ArrayLastValueNode.self,
        ArrayIndexValueNode.self,
        ArrayCountNode.self,
        ArrayAppendNode.self,
        ArrayReplaceValueAtIndexNode.self,
        ArraySplitAtIndexNode.self,
        ArrayQueueNode.self,
        ArrayReverseNode.self,
        ArrayShuffleNode.self,
        ArraySubarrayNode.self,

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

            SampleAndHoldNode.self,
        ])
        return classes
    }
}
