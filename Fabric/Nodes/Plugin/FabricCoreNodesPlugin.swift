//
//  FabricCoreNodesPlugin.swift
//  Fabric
//
//  Created by Claude on 2/6/26.
//

import Foundation
import simd

/// The principal class for Fabric's built-in core nodes plugin.
/// This plugin is embedded within the Fabric framework and provides all standard nodes.
/// It serves as the reference implementation that third-party plugins follow.
@objc(FabricCoreNodesPlugin)
public class FabricCoreNodesPlugin: NSObject, FabricPlugin {

    public static func pluginDidLoad(bundle: Bundle) {
        // Core nodes are already compiled into the framework
    }

    public static func pluginWillUnload() {
        // Core nodes cannot be unloaded
    }

    /// Returns all built-in node classes.
    /// This is the single source of truth for which nodes are included in Fabric.
    public static func additionalNodeClasses() -> [Node.Type] {
        var classes: [Node.Type] = []

        // Camera nodes
        classes.append(contentsOf: [
            PerspectiveCameraNode.self,
            OrthographicCameraNode.self,
        ])

        // Light nodes
        classes.append(contentsOf: [
            DirectionalLightNode.self,
            PointLightNode.self,
        ])

        // Object / Rendering nodes
        classes.append(contentsOf: [
            MeshNode.self,
            ModelMeshNode.self,
            InstancedMeshNode.self,
            InstancedModelMeshNode.self,
            EnvironmentSkyboxNode.self,
        ])

        // Geometry nodes
        classes.append(contentsOf: [
            PlaneGeometryNode.self,
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
            TesselatedTextGeometryNode.self,
            ExtrudedTextGeometryNode.self,
            PixelArrayToGeometryNode.self,
            SuperShapeGeometryNode.self,
        ])

        // Material nodes
        classes.append(contentsOf: [
            BasicColorMaterialNode.self,
            UVMaterialNode.self,
            BasicTextureMaterialNode.self,
            BasicDiffuseMaterialNode.self,
            DepthMaterialNode.self,
            StandardMaterialNode.self,
            PBRMaterialNode.self,
            DisplacementMaterialNode.self,
        ])

        // Texture / Image provider nodes
        classes.append(contentsOf: [
            MovieProviderNode.self,
            CameraProviderNode.self,
            ImageProviderNode.self,
        ])

        #if FABRIC_SYPHON_ENABLED
        classes.append(contentsOf: [
            SyphonClientNode.self,
            SyphonServerNode.self,
        ])
        #endif

        // Image analysis nodes
        classes.append(contentsOf: [
            ForegroundMaskNode.self,
            PersonSegmentationMaskNode.self,
            FacePoseAnalysisNode.self,
            HandPoseAnalysisNode.self,
            LocalVLMNode.self,
            ContourPathNode.self,
            MetalFXSpatialUpsample2xNode.self,
            KeypointDistortNode.self,
            LUTProcessorNode.self,
        ])

        // Image array nodes
        classes.append(contentsOf: [
            ArrayIndexValueNode<FabricImage>.self,
            ArrayCountNode<FabricImage>.self,
            ArrayQueueNode<FabricImage>.self,
            ArrayReplaceValueAtIndexNode<FabricImage>.self,
        ])

        // Macro / Subgraph nodes
        classes.append(contentsOf: [
            SubgraphNode.self,
            DeferredSubgraphNode.self,
            IteratorNode.self,
            IteratorInfoNode.self,
            EnvironmentNode.self,
        ])

        // Boolean parameter nodes
        classes.append(contentsOf: [
            TrueNode.self,
            FalseNode.self,
            BooleanLogicNode.self,
            ArrayFirstValueNode<Bool>.self,
            ArrayLastValueNode<Bool>.self,
            ArrayIndexValueNode<Bool>.self,
            ArrayCountNode<Bool>.self,
            ArrayQueueNode<Bool>.self,
            ArrayReplaceValueAtIndexNode<Bool>.self,
        ])

        // Number parameter nodes
        classes.append(contentsOf: [
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
        ])

        // String parameter nodes
        classes.append(contentsOf: [
            StringNode.self,
            TextFileLoaderNode.self,
            StringJoinNode.self,
            StringComponentNode.self,
            StringLengthNode.self,
            StringRangeNode.self,
            StringWrapNode.self,
            StringRemoveWhitespaceNode.self,
            StringDifferenceNode.self,
            LocalLLMNode.self,
            ArrayFirstValueNode<String>.self,
            ArrayLastValueNode<String>.self,
            ArrayIndexValueNode<String>.self,
            ArrayCountNode<String>.self,
            ArrayQueueNode<String>.self,
            ArrayReplaceValueAtIndexNode<String>.self,
        ])

        // Vector2 parameter nodes
        classes.append(contentsOf: [
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
        ])

        // Vector3 parameter nodes
        classes.append(contentsOf: [
            MakeVector3Node.self,
            Vector3ToFloatNode.self,
            Vector3Distance.self,
            ArrayFirstValueNode<simd_float3>.self,
            ArrayLastValueNode<simd_float3>.self,
            ArrayIndexValueNode<simd_float3>.self,
            ArrayCountNode<simd_float3>.self,
            ArrayQueueNode<simd_float3>.self,
            ArrayReplaceValueAtIndexNode<simd_float3>.self,
        ])

        // Vector4 parameter nodes
        classes.append(contentsOf: [
            MakeVector4Node.self,
            Vector4ToFloatNode.self,
            Vector4Distance.self,
            ArrayFirstValueNode<simd_float4>.self,
            ArrayLastValueNode<simd_float4>.self,
            ArrayIndexValueNode<simd_float4>.self,
            ArrayCountNode<simd_float4>.self,
            ArrayQueueNode<simd_float4>.self,
            ArrayReplaceValueAtIndexNode<simd_float4>.self,
        ])

        // Quaternion nodes
        classes.append(contentsOf: [
            MakeQuaternionNode.self,
        ])

        // Transform (Float Matrix 4x4) nodes
        classes.append(contentsOf: [
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
        ])

        // I/O nodes
        classes.append(OSCReceiveNode.self)
        #if os(macOS)
        classes.append(HIDNode.self)
        #endif
        classes.append(contentsOf: [
            GameControllerNode.self,
            MIDIInputNode.self,
        ])

        // Utility nodes
        classes.append(contentsOf: [
            LogNode.self,
            CursorNode.self,
        ])
        #if os(macOS)
        classes.append(KeyboardNode.self)
        #endif
        classes.append(contentsOf: [
            RenderInfoNode.self,
            ImageDimensions.self,
            PixelsToUnitsNode.self,
            UnitsoPixelsNode.self,
            SignalNode.self,
        ])

        // Sample and Hold nodes (various types)
        classes.append(contentsOf: [
            SampleAndHoldNode<Bool>.self,
            SampleAndHoldNode<Float>.self,
            SampleAndHoldNode<simd_float2>.self,
            SampleAndHoldNode<simd_float3>.self,
            SampleAndHoldNode<simd_float4>.self,
            SampleAndHoldNode<String>.self,
            SampleAndHoldNode<simd_quatf>.self,
            SampleAndHoldNode<simd_float4x4>.self,
            SampleAndHoldNode<FabricImage>.self,
        ])

        // Sample and Hold for arrays
        classes.append(contentsOf: [
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
