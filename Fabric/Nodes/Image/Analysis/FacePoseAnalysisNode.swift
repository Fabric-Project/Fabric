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
            ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Input image to analyze for face landmarks")),

            ("outputFaceContour", NodePort<ContiguousArray<simd_float2>>(name: "Face Contour", kind: .Outlet, description: "Array of points tracing the face outline in unit coordinates")),

            ("outputLeftEye", NodePort<ContiguousArray<simd_float2>>(name: "Left Eye", kind: .Outlet, description: "Array of points tracing the left eye in unit coordinates")),
            ("outputRightEye", NodePort<ContiguousArray<simd_float2>>(name: "Right Eye", kind: .Outlet, description: "Array of points tracing the right eye in unit coordinates")),

            ("outputLeftPupil", NodePort<ContiguousArray<simd_float2>>(name: "Left Pupil", kind: .Outlet, description: "Position of left pupil center in unit coordinates")),
            ("outputRightPupil", NodePort<ContiguousArray<simd_float2>>(name: "Right Pupil", kind: .Outlet, description: "Position of right pupil center in unit coordinates")),

            ("outputLeftEyebrow", NodePort<ContiguousArray<simd_float2>>(name: "Left Eyebrow", kind: .Outlet, description: "Array of points tracing the left eyebrow in unit coordinates")),
            ("outputRightEyebrow", NodePort<ContiguousArray<simd_float2>>(name: "Right Eyebrow", kind: .Outlet, description: "Array of points tracing the right eyebrow in unit coordinates")),

            ("outputNose", NodePort<ContiguousArray<simd_float2>>(name: "Nose", kind: .Outlet, description: "Array of points tracing the nose outline in unit coordinates")),
            ("outputNoseCrest", NodePort<ContiguousArray<simd_float2>>(name: "Nose Crest", kind: .Outlet, description: "Array of points along the nose crest in unit coordinates")),

            ("outputMedianLine", NodePort<ContiguousArray<simd_float2>>(name: "Median Line", kind: .Outlet, description: "Array of points along the face median line in unit coordinates")),

            ("outputInnerLips", NodePort<ContiguousArray<simd_float2>>(name: "Inner Lips", kind: .Outlet, description: "Array of points tracing the inner lip contour in unit coordinates")),
            ("outputOuterLips", NodePort<ContiguousArray<simd_float2>>(name: "Outer Lips", kind: .Outlet, description: "Array of points tracing the outer lip contour in unit coordinates")),

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

    public var outputMedianLine:NodePort<ContiguousArray<simd_float2>> { port(named: "outputMedianLine") }

    public var outputInnerLips:NodePort<ContiguousArray<simd_float2>> { port(named: "outputInnerLips") }
    public var outputOuterLips:NodePort<ContiguousArray<simd_float2>> { port(named: "outputOuterLips") }

    
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
    
    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if self.inputImage.valueDidChange
        {
            let request = VNDetectFaceLandmarksRequest()
            request.preferBackgroundProcessing = false
            
            
            if let inImage = self.inputImage.value,
               let observation = self.faceLandmarksForRequest(request, from: inImage)
            {
                if let faceContour = observation.landmarks?.faceContour
                {
                    let points = faceContour.normalizedPoints.map {
                            
                        return self.normalizedPointToUnits($0, image: inImage, boundingBox: observation.boundingBox)
                    }
                    
                    self.outputFaceContour.send( ContiguousArray(points) )
                }
                
                if let leftEye = observation.landmarks?.leftEye
                {
                    let points = leftEye.normalizedPoints.map {
                            
                        return self.normalizedPointToUnits($0, image: inImage, boundingBox: observation.boundingBox)
                    }
                    
                    self.outputLeftEye.send( ContiguousArray(points) )
                }
                
                if let rightEye = observation.landmarks?.rightEye
                {
                    let points = rightEye.normalizedPoints.map {
                            
                        return self.normalizedPointToUnits($0, image: inImage, boundingBox: observation.boundingBox)
                    }
                    
                    self.outputRightEye.send( ContiguousArray(points) )
                }
                
                if let leftPupil = observation.landmarks?.leftPupil
                {
                    let points = leftPupil.normalizedPoints.map {
                            
                        return self.normalizedPointToUnits($0, image: inImage, boundingBox: observation.boundingBox)
                    }
                    
                    self.outputLeftPupil.send( ContiguousArray(points) )
                }
                
                if let rightPupil = observation.landmarks?.rightPupil
                {
                    let points = rightPupil.normalizedPoints.map {
                            
                        return self.normalizedPointToUnits($0, image: inImage, boundingBox: observation.boundingBox)
                    }
                    
                    self.outputRightPupil.send( ContiguousArray(points) )
                }
                
                if let leftEyebrow = observation.landmarks?.leftEyebrow
                {
                    let points = leftEyebrow.normalizedPoints.map {
                            
                        return self.normalizedPointToUnits($0, image: inImage, boundingBox: observation.boundingBox)
                    }
                    
                    self.outputLeftEyebrow.send( ContiguousArray(points) )
                }
                
                if let rightEyebrow = observation.landmarks?.rightEyebrow
                {
                    let points = rightEyebrow.normalizedPoints.map {
                            
                        return self.normalizedPointToUnits($0, image: inImage, boundingBox: observation.boundingBox)
                    }
                    
                    self.outputRightEyebrow.send( ContiguousArray(points) )
                }
                
                if let nose = observation.landmarks?.nose
                {
                    let points = nose.normalizedPoints.map {
                            
                        return self.normalizedPointToUnits($0, image: inImage, boundingBox: observation.boundingBox)
                    }
                    
                    self.outputNose.send( ContiguousArray(points) )
                }
                
                if let noseCrest = observation.landmarks?.noseCrest
                {
                    let points = noseCrest.normalizedPoints.map {
                            
                        return self.normalizedPointToUnits($0, image: inImage, boundingBox: observation.boundingBox)
                    }
                    
                    self.outputNoseCrest.send( ContiguousArray(points) )
                }
                
                if let medianLine = observation.landmarks?.medianLine
                {
                    let points = medianLine.normalizedPoints.map {
                            
                        return self.normalizedPointToUnits($0, image: inImage, boundingBox: observation.boundingBox)
                    }
                    
                    self.outputMedianLine.send( ContiguousArray(points) )
                }
                
                if let innerLips = observation.landmarks?.innerLips
                {
                    let points = innerLips.normalizedPoints.map {
                            
                        return self.normalizedPointToUnits($0, image: inImage, boundingBox: observation.boundingBox)
                    }
                    
                    self.outputInnerLips.send( ContiguousArray(points) )
                }
                
                if let outerLips = observation.landmarks?.outerLips
                {
                    let points = outerLips.normalizedPoints.map {
                            
                        return self.normalizedPointToUnits($0, image: inImage, boundingBox: observation.boundingBox)
                    }
                    
                    self.outputOuterLips.send( ContiguousArray(points) )
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
    
    private func normalizedPointToUnits(_ point: CGPoint, image: FabricImage, boundingBox: CGRect) -> simd_float2
    {
        let size = image.presentationSize
        let aspect = size.height / size.width
        
        let imagePoint = VNImagePointForFaceLandmarkPoint( simd_float2(x:Float(point.x), y:Float(point.y)), boundingBox,  Int(size.width), Int(size.height))

        return simd_float2(remap(Float(imagePoint.x / size.width), 0.0, 1.0, -1.0, 1.0),
                           remap(Float(imagePoint.y / size.height), 0.0, 1.0, -Float(aspect), Float(aspect)))
    }
        
    private func faceLandmarksForRequest(_ request: VNDetectFaceLandmarksRequest, from image: FabricImage) ->  VNFaceObservation?
    {
        if let inputImage = image.presentationCIImage
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
