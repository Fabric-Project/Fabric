//
//  FacePoseAnalysisNode.swift
//  Fabric
//
//  Created by Anton Marini on 6/28/25.
//

import Foundation
import Satin
import simd
import Metal
import MetalKit
import Vision

public class FacePoseAnalysisNode: Node
{
    override public class var name:String { "Face Pose Analysis" }
    override public class var nodeType:Node.NodeType { .Image(imageType: .Analysis) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Detects face landmarks in an image (via RTMPose-Face6) and outputs them in unit coordinates. Wire a Region Detection node into Region of Interest for accurate tracking — without one this runs on the full frame, which is only accurate if the face already fills most of it. Face6 has no dedicated pupil landmark (Pupil outputs approximate the eye centroid) or median-line group (approximated from the nose bridge)." }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Input image to analyze for face landmarks")),
            ("inputRegionOfInterest", NodePort<simd_float4>(name: "Region of Interest", kind: .Inlet, description: "Region to crop before pose refinement, as (x, y, width, height) normalized bottom-left-origin — wire in from a Region Detection node. Defaults to the full frame when unconnected.")),

            ("outputFaceContour", NodePort<ContiguousArray<simd_float2>>(name: "Face Contour", kind: .Outlet, description: "Array of points tracing the face outline in unit coordinates")),

            ("outputLeftEye", NodePort<ContiguousArray<simd_float2>>(name: "Left Eye", kind: .Outlet, description: "Array of points tracing the left eye in unit coordinates")),
            ("outputRightEye", NodePort<ContiguousArray<simd_float2>>(name: "Right Eye", kind: .Outlet, description: "Array of points tracing the right eye in unit coordinates")),

            ("outputLeftPupil", NodePort<ContiguousArray<simd_float2>>(name: "Left Pupil", kind: .Outlet, description: "Approximate left pupil position (eye centroid) in unit coordinates")),
            ("outputRightPupil", NodePort<ContiguousArray<simd_float2>>(name: "Right Pupil", kind: .Outlet, description: "Approximate right pupil position (eye centroid) in unit coordinates")),

            ("outputLeftEyebrow", NodePort<ContiguousArray<simd_float2>>(name: "Left Eyebrow", kind: .Outlet, description: "Array of points tracing the left eyebrow in unit coordinates")),
            ("outputRightEyebrow", NodePort<ContiguousArray<simd_float2>>(name: "Right Eyebrow", kind: .Outlet, description: "Array of points tracing the right eyebrow in unit coordinates")),

            ("outputNose", NodePort<ContiguousArray<simd_float2>>(name: "Nose", kind: .Outlet, description: "Array of points tracing the nose outline in unit coordinates")),
            ("outputNoseCrest", NodePort<ContiguousArray<simd_float2>>(name: "Nose Crest", kind: .Outlet, description: "Array of points along the nose crest in unit coordinates")),

            ("outputMedianLine", NodePort<ContiguousArray<simd_float2>>(name: "Median Line", kind: .Outlet, description: "Approximate face median line (from the nose bridge) in unit coordinates")),

            ("outputInnerLips", NodePort<ContiguousArray<simd_float2>>(name: "Inner Lips", kind: .Outlet, description: "Array of points tracing the inner lip contour in unit coordinates")),
            ("outputOuterLips", NodePort<ContiguousArray<simd_float2>>(name: "Outer Lips", kind: .Outlet, description: "Array of points tracing the outer lip contour in unit coordinates")),

        ]
    }

    public var inputImage:NodePort<FabricImage>  { port(named: "inputImage") }
    public var inputRegionOfInterest:NodePort<simd_float4> { port(named: "inputRegionOfInterest") }

    public var outputFaceContour:NodePort<ContiguousArray<simd_float2>> { port(named: "outputFaceContour") }

    public var outputLeftEye:NodePort<ContiguousArray<simd_float2>> { port(named: "outputLeftEye") }
    public var outputRightEye:NodePort<ContiguousArray<simd_float2>> { port(named: "outputRightEye") }

    public var outputLeftPupil:NodePort<ContiguousArray<simd_float2>> { port(named: "outputLeftPupil") }
    public var outputRightPupil:NodePort<ContiguousArray<simd_float2>> { port(named: "outputRightPupil") }

    public var outputLeftEyebrow:NodePort<ContiguousArray<simd_float2>> { port(named: "outputLeftEyebrow") }
    public var outputRightEyebrow:NodePort<ContiguousArray<simd_float2>> { port(named: "outputRightEyebrow") }

    public var outputNose:NodePort<ContiguousArray<simd_float2>> { port(named: "outputNose") }
    public var outputNoseCrest:NodePort<ContiguousArray<simd_float2>> { port(named: "outputNoseCrest") }

    public var outputMedianLine:NodePort<ContiguousArray<simd_float2>> { port(named: "outputMedianLine") }

    public var outputInnerLips:NodePort<ContiguousArray<simd_float2>> { port(named: "outputInnerLips") }
    public var outputOuterLips:NodePort<ContiguousArray<simd_float2>> { port(named: "outputOuterLips") }

    private static let fullFrameRegion = simd_float4(0, 0, 1, 1)
    private static let face106KeypointCount = 106

    private var ciContext:CIContext!
    private var lastKeypoints: [simd_float2] = []

    override public func startExecution(renderer:GraphRenderer) throws
    {

        let options = [
            CIContextOption.cacheIntermediates : false,
            CIContextOption.highQualityDownsample : false,
            CIContextOption.workingFormat : CIFormat.RGBAh.rawValue,
            CIContextOption.workingColorSpace : nil,
            CIContextOption.outputColorSpace :nil,
        ] as? [CIContextOption : Any]

        self.ciContext = CIContext(mtlCommandQueue: self.context.commandQueue, options: options)
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if self.inputImage.valueDidChange, let inputImage = self.inputImage.value
        {
            let regionOfInterest = self.inputRegionOfInterest.value ?? Self.fullFrameRegion
            if let keypoints = try? RTMPoseInference.run(
                image: inputImage,
                regionOfInterest: regionOfInterest,
                modelIdentity: .facePose(.tiny),
                keypointCount: Self.face106KeypointCount,
                ciContext: self.ciContext
            )
            {
                self.lastKeypoints = keypoints
            }
        }

        guard let inImage = self.inputImage.value else { return }
        guard self.lastKeypoints.isEmpty == false else { return }

        let aspect = Float(inImage.presentationSize.height / inImage.presentationSize.width)

        self.outputFaceContour.send(self.unitPoints(in: RTMPoseKeypointSchema.face106ContourRange, from: self.lastKeypoints, aspect: aspect))
        self.outputLeftEye.send(self.unitPoints(in: RTMPoseKeypointSchema.face106LeftEyeRange, from: self.lastKeypoints, aspect: aspect))
        self.outputRightEye.send(self.unitPoints(in: RTMPoseKeypointSchema.face106RightEyeRange, from: self.lastKeypoints, aspect: aspect))
        self.outputLeftEyebrow.send(self.unitPoints(in: RTMPoseKeypointSchema.face106LeftEyebrowRange, from: self.lastKeypoints, aspect: aspect))
        self.outputRightEyebrow.send(self.unitPoints(in: RTMPoseKeypointSchema.face106RightEyebrowRange, from: self.lastKeypoints, aspect: aspect))
        self.outputNose.send(self.unitPoints(in: RTMPoseKeypointSchema.face106NoseRange, from: self.lastKeypoints, aspect: aspect))
        self.outputNoseCrest.send(self.unitPoints(in: RTMPoseKeypointSchema.face106NoseCrestRange, from: self.lastKeypoints, aspect: aspect))
        // No explicit median-line group in Face6 — approximated from the nose bridge.
        self.outputMedianLine.send(self.unitPoints(in: RTMPoseKeypointSchema.face106NoseCrestRange, from: self.lastKeypoints, aspect: aspect))
        self.outputInnerLips.send(self.unitPoints(in: RTMPoseKeypointSchema.face106InnerLipsRange, from: self.lastKeypoints, aspect: aspect))
        self.outputOuterLips.send(self.unitPoints(in: RTMPoseKeypointSchema.face106OuterLipsRange, from: self.lastKeypoints, aspect: aspect))

        // No dedicated pupil landmark in Face6 — approximated as the eye region's centroid.
        if let leftPupil = self.centroid(in: RTMPoseKeypointSchema.face106LeftEyeRange, from: self.lastKeypoints)
        {
            self.outputLeftPupil.send([self.unitPoint(from: leftPupil, aspect: aspect)])
        }
        if let rightPupil = self.centroid(in: RTMPoseKeypointSchema.face106RightEyeRange, from: self.lastKeypoints)
        {
            self.outputRightPupil.send([self.unitPoint(from: rightPupil, aspect: aspect)])
        }
    }

    private func unitPoints(in range: Range<Int>, from positions: [simd_float2], aspect: Float) -> ContiguousArray<simd_float2>
    {
        var points = ContiguousArray<simd_float2>()
        points.reserveCapacity(range.count)

        for index in range where positions.indices.contains(index)
        {
            points.append(self.unitPoint(from: positions[index], aspect: aspect))
        }

        return points
    }

    private func centroid(in range: Range<Int>, from positions: [simd_float2]) -> simd_float2?
    {
        let pointsInRange = range.compactMap { positions.indices.contains($0) ? positions[$0] : nil }
        guard pointsInRange.isEmpty == false else { return nil }

        let sum = pointsInRange.reduce(simd_float2(0, 0), +)
        return sum / Float(pointsInRange.count)
    }

    /// `visionNormalizedPoint` is bottom-left-origin, [0,1] — the same space
    /// VNRecognizedPoint.x/y and RTMPoseInference's output both occupy.
    private func unitPoint(from visionNormalizedPoint: simd_float2, aspect: Float) -> simd_float2
    {
        return simd_float2(remap(visionNormalizedPoint.x, 0.0, 1.0, -1.0, 1.0),
                           remap(visionNormalizedPoint.y, 0.0, 1.0, -Float(aspect), Float(aspect)))
    }
}
