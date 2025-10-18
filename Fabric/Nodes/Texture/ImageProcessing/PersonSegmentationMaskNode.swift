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

public class PersonSegmentationMaskNode: Node
{
    override public class var name:String { "Person Segmentation Mask" }
    override public class var nodeType:Node.NodeType { .Image(imageType: .Mask) }
    
    // Ports
    let inputTexturePort:NodePort<EquatableTexture>
    let outputTexturePort:NodePort<EquatableTexture>
    override public var ports: [AnyPort] { [inputTexturePort, outputTexturePort] + super.ports}
    
    @ObservationIgnored private var textureCache:CVMetalTextureCache?
    
    required init(context:Context)
    {
        self.inputTexturePort = NodePort<EquatableTexture>(name: "Image", kind: .Inlet)
        self.outputTexturePort = NodePort<EquatableTexture>(name: "Image", kind: .Outlet)
        
        let _ = CVMetalTextureCacheCreate(kCFAllocatorDefault,
                                          nil,
                                          context.device,
                                          nil,
                                          &self.textureCache)
        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputTexturePort
        case outputTexturePort
    }
    
    override public func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputTexturePort, forKey: .inputTexturePort)
        try container.encode(self.outputTexturePort, forKey: .outputTexturePort)
        
        
        try super.encode(to: encoder)
    }
    
    required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }
        
        self.inputTexturePort = try container.decode(NodePort<EquatableTexture>.self, forKey: .inputTexturePort)
        self.outputTexturePort = try container.decode(NodePort<EquatableTexture>.self, forKey: .outputTexturePort)
        
        let _ = CVMetalTextureCacheCreate(kCFAllocatorDefault,
                                          nil,
                                          decodeContext.documentContext.device,
                                          nil,
                                          &self.textureCache)
        
        try super.init(from:decoder)
    }
    
    override public  func execute(context:GraphExecutionContext,
                                  renderPassDescriptor: MTLRenderPassDescriptor,
                                  commandBuffer: MTLCommandBuffer)
    {
        
        if self.inputTexturePort.valueDidChange
        {
            let request = VNGeneratePersonInstanceMaskRequest()
//            request.qualityLevel = .fast
//            request.outputPixelFormat = kCVPixelFormatType_OneComponent16Half
            
            if let inTex = self.inputTexturePort.value?.texture,
               let maskTex =  self.maskForRequest(request, from: inTex)
            {
                self.outputTexturePort.send( EquatableTexture(texture: maskTex) )
            }
            else
            {
                self.outputTexturePort.send( nil )
            }
        }
    }
    
    private func maskForRequest(_ request: VNGeneratePersonInstanceMaskRequest, from texture:MTLTexture,) -> MTLTexture?
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
            
            let handler = VNImageRequestHandler(ciImage: inputImage)
            
            do {
                // Perform the Vision request
                try handler.perform([request])
                                
                if let observation = request.results?.first
                {
//                    let mask = observation.pixelBuffer
  
                    // Doesnt always work?
                    let mask = try observation.generateMask(forInstances: IndexSet(integer: 1) )

                    CVMetalTextureCacheFlush(self.textureCache!, 0)
                    
                    var cvMask:CVMetalTexture? = nil
                    let success = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                            self.textureCache!,
                                                                            mask,
                                                                            nil,
                                                                            .bgra8Unorm,
                                                                            CVPixelBufferGetWidth(mask),
                                                                            CVPixelBufferGetHeight(mask),
                                                                            0,
                                                                            &cvMask)
                    
                    if success == kCVReturnSuccess, let cvMask
                    {
                        return CVMetalTextureGetTexture(cvMask)
                    }
                }
            }
            catch
            {
                return nil
            }
            
        }
        
        return nil
    }
}
