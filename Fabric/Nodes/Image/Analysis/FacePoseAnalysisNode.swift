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

public class FacePoseAnalysisNode: Node
{
    override public class var name:String { "Face Pose Analysis" }
    override public class var nodeType:Node.NodeType { .Image(imageType: .Analysis) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Detect Face Poses in an Image and outputs in Units" }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet)),
            
            ("outputFaceContour", NodePort<ContiguousArray<simd_float2>>(name: "Face Contour", kind: .Outlet)),
           
            ("outputLeftEye", NodePort<ContiguousArray<simd_float2>>(name: "Left Eye", kind: .Outlet)),
            ("outputRightEye", NodePort<ContiguousArray<simd_float2>>(name: "Right Eye", kind: .Outlet)),

            ("outputLeftPupil", NodePort<ContiguousArray<simd_float2>>(name: "Left Pupil", kind: .Outlet)),
            ("outputRightPupil", NodePort<ContiguousArray<simd_float2>>(name: "Right Pupil", kind: .Outlet)),

            ("outputLeftEyebrow", NodePort<ContiguousArray<simd_float2>>(name: "Left Eyebrow", kind: .Outlet)),
            ("outputRightEyebrow", NodePort<ContiguousArray<simd_float2>>(name: "Right Eyebrow", kind: .Outlet)),

            ("outputNose", NodePort<ContiguousArray<simd_float2>>(name: "Nose", kind: .Outlet)),
            ("outputNoseCrest", NodePort<ContiguousArray<simd_float2>>(name: "Nose Crest", kind: .Outlet)),

        ]
    }

    public var inputImage:NodePort<FabricImage>  { port(named: "inputImage") }

    public var outputFaceContour:NodePort<ContiguousArray<simd_float2>> { port(named: "outputFaceContour") }
    
    public var outputLeftEye:NodePort<ContiguousArray<simd_float2>> { port(named: "outputLeftEye") }
    public var outputRightEye:NodePort<ContiguousArray<simd_float2>> { port(named: "outputRightEye") }

    public var outputLeftPupil:NodePort<ContiguousArray<simd_float2>> { port(named: "outputLeftPupil") }
    public var outputRightPupil:NodePort<ContiguousArray<simd_float2>> { port(named: "outputRightPupil") }

    public var outputLeftEyebrow:NodePort<ContiguousArray<simd_float2>> { port(named: "outputLeftEyebrow") }
    public var outputRightEyebrow:NodePort<ContiguousArray<simd_float2>> { port(named: "outputRightEyebrow") }

    public var outputNose:NodePort<ContiguousArray<simd_float2>> { port(named: "outputNose") }
    public var outputNoseCrest:NodePort<ContiguousArray<simd_float2>> { port(named: "outputNoseCrest") }

    
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
    
    private func normalizedPointToUnits(_ point:CGPoint, imageSize size:CGSize, boundingBox:CGRect) -> simd_float2
    {
        let aspect = size.height / size.width
        
        let imagePoint = VNImagePointForFaceLandmarkPoint( simd_float2(x:Float(point.x), y:Float(point.y)), boundingBox,  Int(size.width), Int(size.height))
        
        let x = remap(Float(imagePoint.x), 0.0, Float(size.width), -1.0, 1.0)
        let y = remap(Float(imagePoint.y), Float(size.height), 0.0, -Float(aspect), Float(aspect))

        return simd_float2(x: x, y: y)
    }
    
//    private func sendLandmark(_ landmark:VNFaceLandmarks2D, toPort:NodePort<ContiguousArray<simd_float2>> )
//    {
//        if let faceContour = observation.landmarks?.faceContour
//        {
//            let points = landmark.normalizedPoints.map {
//                    
//                return self.normalizedPointToUnits($0, imageSize: imageSize, boundingBox: observation.boundingBox)
//            }
//            
//            self.outputFaceContour.send( ContiguousArray(points) )
//        }
//    }
    
    override public  func execute(context:GraphExecutionContext,
                                  renderPassDescriptor: MTLRenderPassDescriptor,
                                  commandBuffer: MTLCommandBuffer)
    {
        if self.inputImage.valueDidChange
        {
//            let request = VNDetectHumanHandPoseRequest()
            let request = VNDetectFaceLandmarksRequest()
            request.preferBackgroundProcessing = false
            
            
            if let inTex = self.inputImage.value?.texture,
               let observation =  self.faceLandmarksForRequest(request, from: inTex)
//               let graphRenderer = context.graphRenderer
            {
                
                let imageSize = CGSize(width: inTex.width, height: inTex.height)
//                let aspect = Float(graphRenderer.renderer.size.height)/Float(graphRenderer.renderer.size.width)
                //let aspect = Float(inTex.height)/Float(inTex.width)

                if let faceContour = observation.landmarks?.faceContour
                {
                    let points = faceContour.normalizedPoints.map {
                            
                        return self.normalizedPointToUnits($0, imageSize: imageSize, boundingBox: observation.boundingBox)
                    }
                    
                    self.outputFaceContour.send( ContiguousArray(points) )
                }
                
                if let leftEye = observation.landmarks?.leftEye
                {
                    let points = leftEye.normalizedPoints.map {
                            
                        return self.normalizedPointToUnits($0, imageSize: imageSize, boundingBox: observation.boundingBox)
                    }
                    
                    self.outputLeftEye.send( ContiguousArray(points) )
                }
                
                if let rightEye = observation.landmarks?.rightEye
                {
                    let points = rightEye.normalizedPoints.map {
                            
                        return self.normalizedPointToUnits($0, imageSize: imageSize, boundingBox: observation.boundingBox)
                    }
                    
                    self.outputRightEye.send( ContiguousArray(points) )
                }
                
                if let leftPupil = observation.landmarks?.leftPupil
                {
                    let points = leftPupil.normalizedPoints.map {
                            
                        return self.normalizedPointToUnits($0, imageSize: imageSize, boundingBox: observation.boundingBox)
                    }
                    
                    self.outputLeftPupil.send( ContiguousArray(points) )
                }
                
                if let rightPupil = observation.landmarks?.rightPupil
                {
                    let points = rightPupil.normalizedPoints.map {
                            
                        return self.normalizedPointToUnits($0, imageSize: imageSize, boundingBox: observation.boundingBox)
                    }
                    
                    self.outputRightPupil.send( ContiguousArray(points) )
                }
                
                if let leftEyebrow = observation.landmarks?.leftEyebrow
                {
                    let points = leftEyebrow.normalizedPoints.map {
                            
                        return self.normalizedPointToUnits($0, imageSize: imageSize, boundingBox: observation.boundingBox)
                    }
                    
                    self.outputLeftEyebrow.send( ContiguousArray(points) )
                }
                
                if let rightEyebrow = observation.landmarks?.rightEyebrow
                {
                    let points = rightEyebrow.normalizedPoints.map {
                            
                        return self.normalizedPointToUnits($0, imageSize: imageSize, boundingBox: observation.boundingBox)
                    }
                    
                    self.outputRightEyebrow.send( ContiguousArray(points) )
                }
                
                
                
                
//                for poseKey in allPoints.
//                {
//                    let faceLandmark = VNFaceLandmarkRegion2D.
//                    
//                    let jointName = VNHumanHandPoseObservation.JointName(rawValue: poseKey)
//
//                    if let portForKey = self.portNameForPoseKey[jointName],
//                       let position = allPoints[poseKey]
//                    {
//                        let port:NodePort<simd_float2> = self.port(named: portForKey)
//                        let ux = remap(Float(position.x), 0.0, 1.0, -1.0, 1.0)
//                        let uy = remap(Float(position.y), 0.0, 1.0, -aspect, aspect)
//                        
//                        port.send( simd_float2(ux, uy) )
//                       //
//                    }
//                }
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
        
    private func faceLandmarksForRequest(_ request: VNDetectFaceLandmarksRequest, from texture:MTLTexture) ->  VNFaceObservation?
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

                guard let observation = request.results?.first as? VNFaceObservation
                else { return nil }
                                
                
                return observation
                
            }
            catch
            {
                return nil
            }
            
        }
        
        return nil
    }
}
