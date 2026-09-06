//
//  HandPoseAnalysisNode.swift
//  Fabric
//
//  Created by Anton Marini on 6/28/25.
//

import Foundation
import Satin
import simd
import Metal
import MetalKit

public class HandPoseAnalysisNode: Node
{
    override public class var name:String { "Hand Pose Analysis" }
    override public class var nodeType:Node.NodeType { .Image(imageType: .Analysis) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Detects a hand pose in an image (via RTMPose-Hand5) and outputs ordered finger-point arrays in unit coordinates. Wire a Region Detection node into Region of Interest for accurate tracking — without one this runs on the full frame, which is only accurate if the hand already fills most of it. Hand Count is retained for backward compatibility but is no longer used; set Max Detections on the upstream Region Detection node instead." }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Input image to analyze for hand poses")),
            ("inputRegionOfInterest", NodePort<simd_float4>(name: "Region of Interest", kind: .Inlet, description: "Region to crop before pose refinement, as (x, y, width, height) normalized bottom-left-origin — wire in from a Region Detection node. Defaults to the full frame when unconnected.")),
            ("inputHandCount", ParameterPort(parameter: IntParameter("Hand Count", 1, 1, 16, .inputfield, "Legacy, no longer used — set Max Detections on the upstream Region Detection node instead"))),

            ("outputThumb", NodePort<ContiguousArray<simd_float2>>(name: "Thumb", kind: .Outlet, description: "Thumb points ordered CMC, MP, IP, Tip in unit coordinates")),
            ("outputIndex", NodePort<ContiguousArray<simd_float2>>(name: "Index", kind: .Outlet, description: "Index finger points ordered MCP, PIP, DIP, Tip in unit coordinates")),
            ("outputMiddle", NodePort<ContiguousArray<simd_float2>>(name: "Middle", kind: .Outlet, description: "Middle finger points ordered MCP, PIP, DIP, Tip in unit coordinates")),
            ("outputRing", NodePort<ContiguousArray<simd_float2>>(name: "Ring", kind: .Outlet, description: "Ring finger points ordered MCP, PIP, DIP, Tip in unit coordinates")),
            ("outputLittle", NodePort<ContiguousArray<simd_float2>>(name: "Little", kind: .Outlet, description: "Little finger points ordered MCP, PIP, DIP, Tip in unit coordinates")),

            ("outputWrist", NodePort<simd_float2>(name: "Wrist", kind: .Outlet, description: "Position of wrist in unit coordinates")),
        ]
    }

    public var inputImage:NodePort<FabricImage>  { port(named: "inputImage") }
    public var inputRegionOfInterest:NodePort<simd_float4> { port(named: "inputRegionOfInterest") }
    public var inputHandCount:ParameterPort<Int> { port(named: "inputHandCount") }

    public var outputThumb:NodePort<ContiguousArray<simd_float2>> { port(named: "outputThumb") }
    public var outputIndex:NodePort<ContiguousArray<simd_float2>> { port(named: "outputIndex") }
    public var outputMiddle:NodePort<ContiguousArray<simd_float2>> { port(named: "outputMiddle") }
    public var outputRing:NodePort<ContiguousArray<simd_float2>> { port(named: "outputRing") }
    public var outputLittle:NodePort<ContiguousArray<simd_float2>> { port(named: "outputLittle") }

    public var outputWrist:NodePort<simd_float2> { port(named: "outputWrist") }

    private static let fullFrameRegion = simd_float4(0, 0, 1, 1)

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

    public override func execute(renderer:GraphRenderer, executionInfo:GraphExecutionInfo, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer)
    throws
    {
        if self.inputImage.valueDidChange, let inputImage = self.inputImage.value
        {
            let regionOfInterest = self.inputRegionOfInterest.value ?? Self.fullFrameRegion
            if let keypoints = try? RTMPoseInference.run(
                image: inputImage,
                regionOfInterest: regionOfInterest,
                modelIdentity: .handPose,
                keypointCount: RTMPoseKeypointSchema.hand21Names.count,
                ciContext: self.ciContext
            )
            {
                self.lastKeypoints = keypoints
            }
        }

        guard let inImage = self.inputImage.value else { return }
        guard self.lastKeypoints.isEmpty == false else { return }

        let aspect = Float(inImage.presentationSize.height / inImage.presentationSize.width)

        self.outputThumb.send(self.unitPoints(at: RTMPoseKeypointSchema.hand21ThumbIndices, in: self.lastKeypoints, aspect: aspect))
        self.outputIndex.send(self.unitPoints(at: RTMPoseKeypointSchema.hand21IndexIndices, in: self.lastKeypoints, aspect: aspect))
        self.outputMiddle.send(self.unitPoints(at: RTMPoseKeypointSchema.hand21MiddleIndices, in: self.lastKeypoints, aspect: aspect))
        self.outputRing.send(self.unitPoints(at: RTMPoseKeypointSchema.hand21RingIndices, in: self.lastKeypoints, aspect: aspect))
        self.outputLittle.send(self.unitPoints(at: RTMPoseKeypointSchema.hand21LittleIndices, in: self.lastKeypoints, aspect: aspect))

        if self.lastKeypoints.indices.contains(RTMPoseKeypointSchema.hand21WristIndex)
        {
            self.outputWrist.send(self.unitPoint(from: self.lastKeypoints[RTMPoseKeypointSchema.hand21WristIndex], aspect: aspect))
        }
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
}
