//
//  ForegroundMaskNode.swift
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
    override public class var nodeDescription: String { "Detect Hand Poses in an Image and outputs in Units" }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputImage", NodePort<EquatableTexture>(name: "Image", kind: .Inlet)),
            ("inputHandCount", ParameterPort(parameter: IntParameter("Hand Count", 1, 1, 16, .inputfield))),
            
            ("outputThumb1", NodePort<simd_float2>(name: "Thumb Tip", kind: .Outlet)),
            ("outputThumb2", NodePort<simd_float2>(name: "Thumb Joint 1", kind: .Outlet)),
            ("outputThumb3", NodePort<simd_float2>(name: "Thumb Joint 2", kind: .Outlet)),
            ("outputThumb4", NodePort<simd_float2>(name: "Thumb Knuckle", kind: .Outlet)),

            ("outputIndex1", NodePort<simd_float2>(name: "Index Tip", kind: .Outlet)),
            ("outputIndex2", NodePort<simd_float2>(name: "Index Joint 1", kind: .Outlet)),
            ("outputIndex3", NodePort<simd_float2>(name: "Index Joint 2", kind: .Outlet)),
            ("outputIndex4", NodePort<simd_float2>(name: "Index Knuckle", kind: .Outlet)),

            ("outputMiddle1", NodePort<simd_float2>(name: "Middle Tip", kind: .Outlet)),
            ("outputMiddle2", NodePort<simd_float2>(name: "Middle Joint 1", kind: .Outlet)),
            ("outputMiddle3", NodePort<simd_float2>(name: "Middle Joint 2", kind: .Outlet)),
            ("outputMiddle4", NodePort<simd_float2>(name: "Middle Knuckle", kind: .Outlet)),

            ("outputRing1", NodePort<simd_float2>(name: "Ring Tip", kind: .Outlet)),
            ("outputRing2", NodePort<simd_float2>(name: "Ring Joint 1", kind: .Outlet)),
            ("outputRing3", NodePort<simd_float2>(name: "Ring Joint 2", kind: .Outlet)),
            ("outputRing4", NodePort<simd_float2>(name: "Ring Knuckle", kind: .Outlet)),

            ("outputLittle1", NodePort<simd_float2>(name: "Little Tip", kind: .Outlet)),
            ("outputLittle2", NodePort<simd_float2>(name: "Little Joint 1", kind: .Outlet)),
            ("outputLittle3", NodePort<simd_float2>(name: "Little Joint 2", kind: .Outlet)),
            ("outputLittle4", NodePort<simd_float2>(name: "Little Knuckle", kind: .Outlet)),

            ("outputWrist", NodePort<simd_float2>(name: "Wrist", kind: .Outlet)),
        ]
    }

    public var inputImage:NodePort<EquatableTexture>  { port(named: "inputImage") }

    public var outputThumb1:NodePort<simd_float2> { port(named: "outputThumb1") }
    public var outputThumb2:NodePort<simd_float2> { port(named: "outputThumb2") }
    public var outputThumb3:NodePort<simd_float2> { port(named: "outputThumb3") }
    public var outputThumb4:NodePort<simd_float2> { port(named: "outputThumb4") }

    public var outputIndex1:NodePort<simd_float2> { port(named: "outputIndex1") }
    public var outputIndex2:NodePort<simd_float2> { port(named: "outputIndex2") }
    public var outputIndex3:NodePort<simd_float2> { port(named: "outputIndex3") }
    public var outputIndex4:NodePort<simd_float2> { port(named: "outputIndex4") }

    public var outputMiddle1:NodePort<simd_float2> { port(named: "outputMiddle1") }
    public var outputMiddle2:NodePort<simd_float2> { port(named: "outputMiddle2") }
    public var outputMiddle3:NodePort<simd_float2> { port(named: "outputMiddle3") }
    public var outputMiddle4:NodePort<simd_float2> { port(named: "outputMiddle4") }

    public var outputRing1:NodePort<simd_float2> { port(named: "outputRing1") }
    public var outputRing2:NodePort<simd_float2> { port(named: "outputRing2") }
    public var outputRing3:NodePort<simd_float2> { port(named: "outputRing3") }
    public var outputRing4:NodePort<simd_float2> { port(named: "outputRing4") }
    
    public var outputLittle1:NodePort<simd_float2> { port(named: "outputLittle1") }
    public var outputLittle2:NodePort<simd_float2> { port(named: "outputLittle2") }
    public var outputLittle3:NodePort<simd_float2> { port(named: "outputLittle3") }
    public var outputLittle4:NodePort<simd_float2> { port(named: "outputLittle4") }

    public var outputWrist:NodePort<simd_float2> { port(named: "outputWrist") }

    private let portNameForPoseKey: [VNHumanHandPoseObservation.JointName: String] = [
        
        .thumbTip : "outputThumb1",
        .thumbIP : "outputThumb2",
        .thumbMP : "outputThumb3",
        .thumbCMC : "outputThumb4",
       
        .indexTip : "outputIndex1",
        .indexDIP : "outputIndex2",
        .indexPIP : "outputIndex3",
        .indexMCP : "outputIndex4",
        
        .middleTip : "outputMiddle1",
        .middleDIP : "outputMiddle2",
        .middlePIP : "outputMiddle3",
        .middleMCP : "outputMiddle4",
        
        .ringTip : "outputRing1",
        .ringDIP : "outputRing2",
        .ringPIP : "outputRing3",
        .ringMCP : "outputRing4",
        
        .littleTip : "outputLittle1",
        .littleDIP : "outputLittle2",
        .littlePIP : "outputLittle3",
        .littleMCP : "outputLittle4",
        
        .wrist : "outputWrist",
        
        ]
    
    private var ciContext:CIContext!
    
    override public func startExecution(context: GraphExecutionContext) {

        if let commandQueue = context.graphRenderer?.commandQueue
        {
            let options = [
                CIContextOption.cacheIntermediates : false,
                CIContextOption.highQualityDownsample : false,
                CIContextOption.workingFormat : CIFormat.RGBAh.rawValue,
                CIContextOption.workingColorSpace : nil,
                CIContextOption.outputColorSpace :nil,
            ] as? [CIContextOption : Any]
            
            self.ciContext = CIContext(mtlCommandQueue: commandQueue, options: options)
        }
    }
    
    override public  func execute(context:GraphExecutionContext,
                                  renderPassDescriptor: MTLRenderPassDescriptor,
                                  commandBuffer: MTLCommandBuffer)
    {
        if self.inputImage.valueDidChange
        {
            let request = VNDetectHumanHandPoseRequest()
            request.preferBackgroundProcessing = false
            request.maximumHandCount = 1
            
            if let inTex = self.inputImage.value?.texture,
               let allPoints =  self.handPointsForRequest(request, from: inTex),
               let graphRenderer = context.graphRenderer
            {
                
                let aspect = Float(inTex.height)/Float(inTex.width)
                let size = simd_float2(x: graphRenderer.renderer.size.width,
                                       y: graphRenderer.renderer.size.height)
                
                for poseKey in allPoints.keys
                {
                    let jointName = VNHumanHandPoseObservation.JointName(rawValue: poseKey)

                    if let portForKey = self.portNameForPoseKey[jointName],
                       let position = allPoints[poseKey]
                    {
                        let port:NodePort<simd_float2> = self.port(named: portForKey)
                        let ux = remap(Float(position.x), 0.0, 1.0, -1.0, 1.0)
                        let uy = remap(Float(position.y), 0.0, 1.0, -aspect, aspect)
                        
                        port.send( simd_float2(ux, uy) )
                       //
                    }
                }
//                for position in handPoints
//                {
//                    let px = remap(position.x, 0.0, 1.0, 0, size.x)
//                    let py = remap(position.y, 0.0, 1.0, 0, size.y)
//                    
//                    let ux = remap(position.x, 0.0, 1.0, -1.0, 1.0)
//                    let uy = remap(position.y, 0.0, 1.0, -aspect, aspect)
//                    
//                    normalizedArray.append(simd_float2( position.x, position.y) )
//                    pixelsArray.append(simd_float2(x: px, y: py))
//                    unitsArray.append(simd_float3(x: ux, y: uy, z: 0))
//                }
//                
//                self.outputHandPointsNormalized.send( normalizedArray )
//                self.outputHandPointsUnits.send( unitsArray )
//                self.outputHandPointsPixels.send( handPoints )
            }
//            else
//            {
//                self.outputHandPointsPixels.send( nil )
//            }
        }
    }
        
    private func handPointsForRequest(_ request: VNDetectHumanHandPoseRequest, from texture:MTLTexture) ->  [VNRecognizedPointKey : VNRecognizedPoint]?
    {
        if let inputImage = CIImage(mtlTexture: texture)
        {
            for computeDevice in MLComputeDevice.allComputeDevices
            {
                switch computeDevice
                {
                case .neuralEngine(let aneDevice):
                    request.setComputeDevice(.neuralEngine(aneDevice), for: .main)
                    request.setComputeDevice(.neuralEngine(aneDevice), for: .postProcessing)
                    
//                case .gpu(let gpu):
//                    request.setComputeDevice(.gpu(gpu), for: .main)
//                    request.setComputeDevice(.gpu(gpu), for: .postProcessing)
                    
                default:
                    break
                }
            }
            
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
