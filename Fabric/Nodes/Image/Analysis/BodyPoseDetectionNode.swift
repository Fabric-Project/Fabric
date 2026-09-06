//
//  BodyPoseDetectionNode.swift
//  Fabric
//

import CoreImage
import Foundation
import Satin
import Vision
import simd

/// Detects a 17-point COCO body pose (via RTMPose body) within a caller-
/// supplied region of interest. Wire a Region Detection node's output into
/// Region of Interest — without one this runs on the full frame, accurate
/// only if a person already fills most of it.
public class BodyPoseDetectionNode: Node
{
    override public class var name: String { "Body Pose Detection" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .Analysis) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Detects a 17-point COCO body pose in an image (via RTMPose) and outputs it in unit coordinates. Wire a Region Detection node into Region of Interest for accurate tracking." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Input image to analyze for a body pose")),
            ("inputRegionOfInterest", NodePort<simd_float4>(name: "Region of Interest", kind: .Inlet, description: "Region to crop before pose refinement, as (x, y, width, height) normalized bottom-left-origin — wire in from a Region Detection node. Defaults to the full frame when unconnected.")),
            ("inputModelTier", ParameterPort(parameter: StringParameter("Model Tier", "Tiny", ["Tiny", "Small", "Medium"], .dropdown, "RTMPose body model size — smaller is faster, larger is more accurate"))),

            ("outputKeypoints", NodePort<ContiguousArray<simd_float2>>(name: "Keypoints", kind: .Outlet, description: "All 17 COCO body keypoints, ordered nose, leftEye, rightEye, leftEar, rightEar, leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist, leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle — in unit coordinates")),
            ("outputHead", NodePort<ContiguousArray<simd_float2>>(name: "Head", kind: .Outlet, description: "Nose, eyes, and ears in unit coordinates")),
            ("outputTorso", NodePort<ContiguousArray<simd_float2>>(name: "Torso", kind: .Outlet, description: "Shoulders and hips in unit coordinates")),
            ("outputLeftArm", NodePort<ContiguousArray<simd_float2>>(name: "Left Arm", kind: .Outlet, description: "Left shoulder, elbow, wrist in unit coordinates")),
            ("outputRightArm", NodePort<ContiguousArray<simd_float2>>(name: "Right Arm", kind: .Outlet, description: "Right shoulder, elbow, wrist in unit coordinates")),
            ("outputLeftLeg", NodePort<ContiguousArray<simd_float2>>(name: "Left Leg", kind: .Outlet, description: "Left hip, knee, ankle in unit coordinates")),
            ("outputRightLeg", NodePort<ContiguousArray<simd_float2>>(name: "Right Leg", kind: .Outlet, description: "Right hip, knee, ankle in unit coordinates")),
        ]
    }

    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var inputRegionOfInterest: NodePort<simd_float4> { port(named: "inputRegionOfInterest") }
    public var inputModelTier: ParameterPort<String> { port(named: "inputModelTier") }

    public var outputKeypoints: NodePort<ContiguousArray<simd_float2>> { port(named: "outputKeypoints") }
    public var outputHead: NodePort<ContiguousArray<simd_float2>> { port(named: "outputHead") }
    public var outputTorso: NodePort<ContiguousArray<simd_float2>> { port(named: "outputTorso") }
    public var outputLeftArm: NodePort<ContiguousArray<simd_float2>> { port(named: "outputLeftArm") }
    public var outputRightArm: NodePort<ContiguousArray<simd_float2>> { port(named: "outputRightArm") }
    public var outputLeftLeg: NodePort<ContiguousArray<simd_float2>> { port(named: "outputLeftLeg") }
    public var outputRightLeg: NodePort<ContiguousArray<simd_float2>> { port(named: "outputRightLeg") }

    private static let fullFrameRegion = simd_float4(0, 0, 1, 1)

    private var ciContext: CIContext!
    private var lastKeypoints: [simd_float2] = []

    override public func startExecution(renderer: GraphRenderer) throws
    {
        let options = [
            CIContextOption.cacheIntermediates: false,
            CIContextOption.highQualityDownsample: false,
            CIContextOption.workingFormat: CIFormat.RGBAh.rawValue,
            CIContextOption.workingColorSpace: nil,
            CIContextOption.outputColorSpace: nil,
        ] as? [CIContextOption: Any]

        self.ciContext = CIContext(mtlCommandQueue: self.context.commandQueue, options: options)
    }

    override public func execute(renderer: GraphRenderer, executionInfo: GraphExecutionInfo, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws
    {
        if self.inputImage.valueDidChange, let inputImage = self.inputImage.value
        {
            let regionOfInterest = self.inputRegionOfInterest.value ?? Self.fullFrameRegion
            let tier = Self.modelTier(fromLabel: self.inputModelTier.value ?? "Tiny")
            if let keypoints = try? RTMPoseInference.run(
                image: inputImage,
                regionOfInterest: regionOfInterest,
                modelIdentity: .bodyPose(tier),
                keypointCount: RTMPoseKeypointSchema.coco17BodyNames.count,
                ciContext: self.ciContext
            )
            {
                self.lastKeypoints = keypoints
            }
        }

        guard let inImage = self.inputImage.value else { return }
        guard self.lastKeypoints.isEmpty == false else { return }

        let aspect = Float(inImage.presentationSize.height / inImage.presentationSize.width)

        self.outputKeypoints.send(self.unitPoints(at: Array(self.lastKeypoints.indices), in: self.lastKeypoints, aspect: aspect))
        self.outputHead.send(self.unitPoints(at: RTMPoseKeypointSchema.coco17HeadIndices, in: self.lastKeypoints, aspect: aspect))
        self.outputTorso.send(self.unitPoints(at: RTMPoseKeypointSchema.coco17TorsoIndices, in: self.lastKeypoints, aspect: aspect))
        self.outputLeftArm.send(self.unitPoints(at: RTMPoseKeypointSchema.coco17LeftArmIndices, in: self.lastKeypoints, aspect: aspect))
        self.outputRightArm.send(self.unitPoints(at: RTMPoseKeypointSchema.coco17RightArmIndices, in: self.lastKeypoints, aspect: aspect))
        self.outputLeftLeg.send(self.unitPoints(at: RTMPoseKeypointSchema.coco17LeftLegIndices, in: self.lastKeypoints, aspect: aspect))
        self.outputRightLeg.send(self.unitPoints(at: RTMPoseKeypointSchema.coco17RightLegIndices, in: self.lastKeypoints, aspect: aspect))
    }

    private func unitPoints(at indices: [Int], in positions: [simd_float2], aspect: Float) -> ContiguousArray<simd_float2>
    {
        var points = ContiguousArray<simd_float2>()
        points.reserveCapacity(indices.count)

        for index in indices where positions.indices.contains(index)
        {
            points.append(self.unitPoint(from: positions[index], aspect: aspect))
        }

        return points
    }

    /// `visionNormalizedPoint` is bottom-left-origin, [0,1] — the same space
    /// VNRecognizedPoint.x/y and RTMPoseInference's output both occupy.
    private func unitPoint(from visionNormalizedPoint: simd_float2, aspect: Float) -> simd_float2
    {
        return simd_float2(remap(visionNormalizedPoint.x, 0.0, 1.0, -1.0, 1.0),
                           remap(visionNormalizedPoint.y, 0.0, 1.0, -aspect, aspect))
    }

    private static func modelTier(fromLabel label: String) -> PoseModelTier
    {
        PoseModelTier.allCases.first { $0.rawValue == label } ?? .tiny
    }
}
