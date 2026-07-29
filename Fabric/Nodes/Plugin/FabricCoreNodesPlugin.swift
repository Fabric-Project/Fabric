//
//  FabricCoreNodesPlugin.swift
//  Fabric
//
//  Created by Anton Marini on 7/24/26.
//

import Foundation
import Satin
import simd

/// Embedded plugin that provides Fabric's built-in nodes.
///
/// This is intentionally loaded by `PluginLoader` before external bundles so
/// built-in nodes dogfood the same registry path as third-party nodes.
public final class FabricCoreNodesPlugin: NSObject, FabricPlugin
{
    public static let pluginID = "graphics.fabric.CoreNodes"

    public static func pluginDidLoad(bundle: Bundle) {}
    public static func pluginWillUnload() {}

    public static func additionalNodeClasses() -> [Node.Type]
    {
        cameraNodeClasses
        + lightNodeClasses
        + objectNodeClasses
        + geometryNodeClasses
        + materialNodeClasses
        + textureNodeClasses
        + parameterNodeClasses
        + ioNodeClasses
        + macroNodeClasses
        + utilityClasses
    }

    public static func dynamicNodeWrappers() -> [NodeClassWrapper]
    {
        let bundle = Bundle.module
        var nodes: [NodeClassWrapper] = []

        for imageEffectType in Node.NodeType.ImageType.allCases
        {
            let singleChannelEffects = "Effects/\(imageEffectType.rawValue)"
            let twoChannelEffects = "EffectsTwoChannel/\(imageEffectType.rawValue)"
            let threeChannelEffects = "EffectsThreeChannel/\(imageEffectType.rawValue)"
            let computeSubdir = "Compute/\(imageEffectType.rawValue)"

            guard let singleChannelEffects = bundle.urls(forResourcesWithExtension: "metal", subdirectory: singleChannelEffects),
                  let twoChannelEffects = bundle.urls(forResourcesWithExtension: "metal", subdirectory: twoChannelEffects),
                  let threeChannelEffects = bundle.urls(forResourcesWithExtension: "metal", subdirectory: threeChannelEffects),
                  let singleChannelComputeEffects = bundle.urls(forResourcesWithExtension: "metal", subdirectory: computeSubdir)
            else
            {
                continue
            }

            for fileURL in singleChannelEffects + twoChannelEffects + threeChannelEffects
            {
                nodes.append(NodeClassWrapper(nodeClass: BaseImageNode.self,
                                              nodeType: .Image(imageType: imageEffectType),
                                              fileURL: fileURL,
                                              nodeName: fileURLToName(fileURL: fileURL),
                                              nodeDescription: shaderDescription(from: fileURL) ?? BaseImageNode.nodeDescription,
                                              pluginBundleID: pluginID))
            }

            for fileURL in singleChannelComputeEffects
            {
                nodes.append(NodeClassWrapper(nodeClass: BaseTextureComputeProcessorNode.self,
                                              nodeType: .Image(imageType: imageEffectType),
                                              fileURL: fileURL,
                                              nodeName: fileURLToName(fileURL: fileURL),
                                              nodeDescription: shaderDescription(from: fileURL) ?? BaseTextureComputeProcessorNode.nodeDescription,
                                              pluginBundleID: pluginID))
            }
        }

        return nodes.sorted { $0.nodeName < $1.nodeName }
    }

    private static func fileURLToName(fileURL: URL) -> String
    {
        let nodeName = fileURL.deletingPathExtension().lastPathComponent.replacing("ImageNode", with: "")
        return nodeName.titleCase
    }

    private static func shaderDescription(from fileURL: URL) -> String?
    {
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
              let source = String(data: data, encoding: .utf8)
        else
        {
            return nil
        }

        for line in source.split(separator: "\n", maxSplits: 20, omittingEmptySubsequences: false)
        {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("// description:") else { continue }

            let description = trimmed.dropFirst("// description:".count).trimmingCharacters(in: .whitespaces)
            return description.isEmpty ? nil : description
        }

        return nil
    }

    private static let cameraNodeClasses: [Node.Type] = [
        PerspectiveCameraNode.self,
        OrthographicCameraNode.self,
    ]

    private static let lightNodeClasses: [Node.Type] = [
        DirectionalLightNode.self,
        PointLightNode.self,
        SpotLightNode.self,
    ]

    private static let objectNodeClasses: [Node.Type] = [
        MeshNode.self,
        ModelMeshNode.self,
        InstancedMeshNode.self,
        InstancedModelMeshNode.self,
        EnvironmentSkyboxNode.self,
        ImageMeshNode.self,
    ]

    private static let geometryNodeClasses: [Node.Type] = [
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

    private static let materialNodeClasses: [Node.Type] = [
        PassThroughNode<Material>.self,
        BasicColorMaterialNode.self,
        UVMaterialNode.self,
        BasicTextureMaterialNode.self,
        BasicDiffuseMaterialNode.self,
        DepthMaterialNode.self,
        StandardMaterialNode.self,
        PBRMaterialNode.self,
        DisplacementMaterialNode.self,
    ]

    private static var textureNodeClasses: [Node.Type]
    {
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
            GaussianBlurChannelsNode.self,
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
            ImageResampleNode.self,
        ])
        return classes
    }

    private static let macroNodeClasses: [Node.Type] = [
        SubgraphNode.self,
        DeferredSubgraphNode.self,
        IteratorNode.self,
        IteratorInfoNode.self,
        EnvironmentNode.self,
    ]

    private static let parameterNodeClasses: [Node.Type] = [
        DistanceNode.self,
        EasingNode.self,
        TweenNode.self,
        RepeatNode.self,
        RippleRepeatNode.self,
        PairwiseDistanceArrayNode.self,
        ArrayRangeInterpolateNode.self,
        ArrayResampleTypeAgnosticNode.self,
        PassThroughNode<Bool>.self,
        BooleanLogicNode.self,
        PassThroughNode<Float>.self,
        PassThroughNode<Int>.self,
        CurrentTimeNode.self,
        SystemTimeNode.self,
        TimestampNode.self,
        TimelineNode.self,
        NumberUnaryOperator.self,
        NumberBinaryOperator.self,
        NumberLogicOperator.self,
        NumberRoundNode.self,
        NumberClampNode.self,
        NumberRemapNode.self,
        NumberIntegralNode.self,
        NumberSmoothNode.self,
        MathExpressionNode.self,
        GradientNoiseNode.self,
        AudioSpectrumNode.self,
        PassThroughNode<simd_float2>.self,
        PassThroughNode<simd_float3>.self,
        PassThroughNode<simd_float4>.self,
        ComposeVectorNode.self,
        DecomposeVectorNode.self,
        ComposeVectorArrayNode.self,
        DecomposeVectorArrayNode.self,
        PassThroughNode<simd_quatf>.self,
        ComposeOrientationNode.self,
        DecomposeOrientationNode.self,
        ComposeOrientationArrayNode.self,
        DecomposeOrientationArrayNode.self,
        PassThroughNode<simd_float4x4>.self,
        ComposeTransformNode.self,
        DecomposeTransformNode.self,
        TranslateTransformNode.self,
        RotateTransformNode.self,
        ScaleTransformNode.self,
        TransposeTransformNode.self,
        InvertTransformNode.self,
        ComposeTransformArrayNode.self,
        DecomposeTransformArrayNode.self,
        GeometryToTransformArrayNode.self,
        ColorPassThroughNode.self,
        MakeColorNode.self,
        PassThroughNode<String>.self,
        StringTrimNode.self,
        StringLengthNode.self,
        StringRangeNode.self,
        StringWrapNode.self,
        StringCaseNode.self,
        StringComparisonNode.self,
        StringFormatterNode.self,
        StringScannerNode.self,
        StringJoinNode.self,
        StringSplitNode.self,
        StringDifferenceNode.self,
        TimestampFormatterNode.self,
        TimecodeFormatterNode.self,
        LocalLLMNode.self,
        DirectoryScannerNode.self,
        TextFileLoaderNode.self,
        PassThroughNode<Dictionary<String, PortValue>>.self,
        PassThroughNode<Dictionary<String, Bool>>.self,
        PassThroughNode<Dictionary<String, Int>>.self,
        PassThroughNode<Dictionary<String, Float>>.self,
        PassThroughNode<Dictionary<String, String>>.self,
        PassThroughNode<Dictionary<String, simd_float2>>.self,
        PassThroughNode<Dictionary<String, simd_float3>>.self,
        PassThroughNode<Dictionary<String, simd_float4>>.self,
        PassThroughNode<Dictionary<String, simd_quatf>>.self,
        PassThroughNode<Dictionary<String, simd_float4x4>>.self,
        PassThroughNode<Dictionary<String, Geometry>>.self,
        PassThroughNode<Dictionary<String, Material>>.self,
        PassThroughNode<Dictionary<String, FabricImage>>.self,
        ComposeDictionaryNode.self,
        DecomposeDictionaryNode.self,
        DictionarySetValueForKeyNode.self,
        DictionaryValueForKeyNode.self,
        DictionaryCountNode.self,
        DictionaryHasKeyNode.self,
        DictionaryRemoveKeyNode.self,
        DictionaryMergeNode.self,
        DictionaryFromJSONStringNode.self,
        ArrayCountNode.self,
        ArrayFirstValueNode.self,
        ArrayLastValueNode.self,
        ArrayIndexValueNode.self,
        ArrayAppendNode.self,
        ArrayReplaceValueAtIndexNode.self,
        ArraySplitAtIndexNode.self,
        ArraySubarrayNode.self,
        ArrayQueueNode.self,
        ArrayReverseNode.self,
        ArrayShuffleNode.self,
        LinePointsNode.self,
        RingPointsNode.self,
        GridPointsNode.self,
        PolyLineSimplifyNode.self,
    ]

    private static var ioNodeClasses: [Node.Type]
    {
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

    private static var utilityClasses: [Node.Type]
    {
        var classes: [Node.Type] = [
            LogNode.self,
            JavaScriptNode.self,
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
            SwitchNode.self,
            GateNode.self,
            MatrixSwitchNode.self,
            SampleAndHoldNode.self,
        ])
        return classes
    }
}
