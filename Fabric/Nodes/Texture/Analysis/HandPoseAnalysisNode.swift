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
    override public class var nodeType:Node.NodeType { .Image(imageType: .ImageAnalysis) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Detect Hand Poses in an Image" }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputImage", NodePort<EquatableTexture>(name: "Image", kind: .Inlet)),
            ("outputHandPointsPixels", NodePort<ContiguousArray<simd_float2>>(name: "Hand Point Pixels", kind: .Outlet)),
            ("outputHandPointsUnits", NodePort<ContiguousArray<simd_float3>>(name: "Hand Points Units", kind: .Outlet)),
        ]
    }

    public var inputImage:NodePort<EquatableTexture>  { port(named: "inputImage") }
    public var outputHandPointsPixels:NodePort<ContiguousArray<simd_float2>> { port(named: "outputHandPointsPixels") }
    public var outputHandPointsUnits:NodePort<ContiguousArray<simd_float3>> { port(named: "outputHandPointsUnits") }

//    private var sequenceRequestHandler = VNSequenceRequestHandler()
    
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
               let handPoints =  self.handPointsForRequest(request, from: inTex),
               let graphRenderer = context.graphRenderer                
            {
                var pixelsArray:ContiguousArray<simd_float2> = ContiguousArray<simd_float2>()
                var unitsArray:ContiguousArray<simd_float3> = ContiguousArray<simd_float3>()
                
                pixelsArray.reserveCapacity(21)
                unitsArray.reserveCapacity(21)
                
                let aspect = graphRenderer.renderer.size.height/graphRenderer.renderer.size.width
                let size = simd_float2(x: graphRenderer.renderer.size.width,
                                       y: graphRenderer.renderer.size.height)
                
                for position in handPoints
                {
                    
                    let px = remap(position.x, 0.0, 1.0, 0, size.x)
                    let py = remap(position.y, 0.0, 1.0, 0, size.y)
                    
                    let ux = remap(position.x, 0.0, 1.0, -1.0, 1.0)
                    let uy = remap(position.y, 0.0, 1.0, -aspect, aspect)
                    
                    pixelsArray.append(simd_float2(x: px, y: py))
                    unitsArray.append(simd_float3(x: ux, y: uy, z: 0))
                }
                
                self.outputHandPointsUnits.send( unitsArray )
                self.outputHandPointsPixels.send( handPoints )
                
                
            }
            else
            {
                self.outputHandPointsPixels.send( nil )
            }
        }
    }
    
    private func handPointsForRequest(_ request: VNDetectHumanHandPoseRequest, from texture:MTLTexture) -> ContiguousArray<simd_float2>?
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
                
                var points:ContiguousArray<simd_float2> = ContiguousArray<simd_float2>()
                points.reserveCapacity(21)

                for (key, point) in allPoints
                {
                    points.append(simd_float2(Float(point.location.x), Float(point.location.y)))
                }
                
                return points
            }
            catch
            {
                return nil
            }
            
        }
        
        return nil
    }
}
