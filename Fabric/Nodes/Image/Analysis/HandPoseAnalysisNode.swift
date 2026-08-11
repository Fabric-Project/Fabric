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
import Vision

public class HandPoseAnalysisNode: Node
{
    override public class var name:String { "Hand Pose Analysis" }
    override public class var nodeType:Node.NodeType { .Image(imageType: .Analysis) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Detects a hand pose in an image and outputs ordered finger-point arrays in unit coordinates" }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Input image to analyze for hand poses")),
            ("inputHandCount", ParameterPort(parameter: IntParameter("Hand Count", 1, 1, 16, .inputfield, "Maximum number of hands to detect"))),

            ("outputThumb", NodePort<ContiguousArray<simd_float2>>(name: "Thumb", kind: .Outlet, description: "Thumb points ordered CMC, MP, IP, Tip in unit coordinates")),
            ("outputIndex", NodePort<ContiguousArray<simd_float2>>(name: "Index", kind: .Outlet, description: "Index finger points ordered MCP, PIP, DIP, Tip in unit coordinates")),
            ("outputMiddle", NodePort<ContiguousArray<simd_float2>>(name: "Middle", kind: .Outlet, description: "Middle finger points ordered MCP, PIP, DIP, Tip in unit coordinates")),
            ("outputRing", NodePort<ContiguousArray<simd_float2>>(name: "Ring", kind: .Outlet, description: "Ring finger points ordered MCP, PIP, DIP, Tip in unit coordinates")),
            ("outputLittle", NodePort<ContiguousArray<simd_float2>>(name: "Little", kind: .Outlet, description: "Little finger points ordered MCP, PIP, DIP, Tip in unit coordinates")),

            ("outputWrist", NodePort<simd_float2>(name: "Wrist", kind: .Outlet, description: "Position of wrist in unit coordinates")),
        ]
    }

    public var inputImage:NodePort<FabricImage>  { port(named: "inputImage") }

    public var outputThumb:NodePort<ContiguousArray<simd_float2>> { port(named: "outputThumb") }
    public var outputIndex:NodePort<ContiguousArray<simd_float2>> { port(named: "outputIndex") }
    public var outputMiddle:NodePort<ContiguousArray<simd_float2>> { port(named: "outputMiddle") }
    public var outputRing:NodePort<ContiguousArray<simd_float2>> { port(named: "outputRing") }
    public var outputLittle:NodePort<ContiguousArray<simd_float2>> { port(named: "outputLittle") }

    public var outputWrist:NodePort<simd_float2> { port(named: "outputWrist") }

    private static let thumbJoints: [VNHumanHandPoseObservation.JointName] = [.thumbCMC, .thumbMP, .thumbIP, .thumbTip]
    private static let indexJoints: [VNHumanHandPoseObservation.JointName] = [.indexMCP, .indexPIP, .indexDIP, .indexTip]
    private static let middleJoints: [VNHumanHandPoseObservation.JointName] = [.middleMCP, .middlePIP, .middleDIP, .middleTip]
    private static let ringJoints: [VNHumanHandPoseObservation.JointName] = [.ringMCP, .ringPIP, .ringDIP, .ringTip]
    private static let littleJoints: [VNHumanHandPoseObservation.JointName] = [.littleMCP, .littlePIP, .littleDIP, .littleTip]
    
    private var ciContext:CIContext!
    
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
        if self.inputImage.valueDidChange
        {
            let request = VNDetectHumanHandPoseRequest()
            request.preferBackgroundProcessing = false
            request.maximumHandCount = 1
            
            if let inTex = self.inputImage.value?.texture,
               let allPoints =  self.handPointsForRequest(request, from: inTex)
            {
                let aspect = Float(inTex.height)/Float(inTex.width)

                if let thumbPoints = self.unitPoints(for: Self.thumbJoints, from: allPoints, aspect: aspect)
                {
                    self.outputThumb.send(thumbPoints)
                }

                if let indexPoints = self.unitPoints(for: Self.indexJoints, from: allPoints, aspect: aspect)
                {
                    self.outputIndex.send(indexPoints)
                }

                if let middlePoints = self.unitPoints(for: Self.middleJoints, from: allPoints, aspect: aspect)
                {
                    self.outputMiddle.send(middlePoints)
                }

                if let ringPoints = self.unitPoints(for: Self.ringJoints, from: allPoints, aspect: aspect)
                {
                    self.outputRing.send(ringPoints)
                }

                if let littlePoints = self.unitPoints(for: Self.littleJoints, from: allPoints, aspect: aspect)
                {
                    self.outputLittle.send(littlePoints)
                }

                if let wrist = allPoints[VNHumanHandPoseObservation.JointName.wrist.rawValue]
                {
                    self.outputWrist.send(self.unitPoint(from: wrist, aspect: aspect))
                }
            }
        }
    }

    private func unitPoints(for joints: [VNHumanHandPoseObservation.JointName],
                            from recognizedPoints: [VNRecognizedPointKey: VNRecognizedPoint],
                            aspect: Float) -> ContiguousArray<simd_float2>?
    {
        var points = ContiguousArray<simd_float2>()
        points.reserveCapacity(joints.count)

        for joint in joints
        {
            guard let recognizedPoint = recognizedPoints[joint.rawValue] else { return nil }
            points.append(self.unitPoint(from: recognizedPoint, aspect: aspect))
        }

        return points
    }

    private func unitPoint(from recognizedPoint: VNRecognizedPoint, aspect: Float) -> simd_float2
    {
        let x = remap(Float(recognizedPoint.x), 0.0, 1.0, -1.0, 1.0)
        let y = remap(Float(recognizedPoint.y), 0.0, 1.0, -aspect, aspect)
        return simd_float2(x, y)
    }
        
    private func handPointsForRequest(_ request: VNDetectHumanHandPoseRequest, from texture:MTLTexture) ->  [VNRecognizedPointKey : VNRecognizedPoint]?
    {
        if let inputImage = CIImage(mtlTexture: texture)
        {
//            for computeDevice in MLComputeDevice.allComputeDevices
//            {
//                switch computeDevice
//                {
//                case .neuralEngine(let aneDevice):
//                    request.setComputeDevice(.neuralEngine(aneDevice), for: .main)
//                    request.setComputeDevice(.neuralEngine(aneDevice), for: .postProcessing)
//                    
////                case .gpu(let gpu):
////                    request.setComputeDevice(.gpu(gpu), for: .main)
////                    request.setComputeDevice(.gpu(gpu), for: .postProcessing)
//                    
//                default:
//                    break
//                }
//            }
            
            let handler = VNImageRequestHandler(ciImage: inputImage, options: [.ciContext : self.ciContext!])
            
            do {

                // Perform the Vision request
                try handler.perform([request])

                guard let observation = request.results?.first as? VNRecognizedPointsObservation
                else { return nil }
                
                let allPoints: [VNRecognizedPointKey : VNRecognizedPoint] = try observation.recognizedPoints(forGroupKey: .all)
                
                return allPoints
                
            }
            catch
            {
                return nil
            }
            
        }
        
        return nil
    }
}
