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

public class ForegroundMaskNode: Node
{
    override public class var name:String { "Foreground Mask" }
    override public class var nodeType:Node.NodeType { .Image(imageType: .Mask) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Creates a mask from a the most foreground object in the image."}

    // Ports
    let inputTexturePort:NodePort<FabricImage>
    let outputTexturePort:NodePort<FabricImage>
    override public var ports: [Port] { [inputTexturePort, outputTexturePort] + super.ports}
        
    required init(context:Context)
    {
        self.inputTexturePort = NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Input image to analyze")
        self.outputTexturePort = NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "Foreground object mask")
        
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
        
        self.inputTexturePort = try container.decode(NodePort<FabricImage>.self, forKey: .inputTexturePort)
        self.outputTexturePort = try container.decode(NodePort<FabricImage>.self, forKey: .outputTexturePort)
        
        try super.init(from:decoder)
    }
    
    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        
        if self.inputTexturePort.valueDidChange
        {
            if  let inImage = self.inputTexturePort.value,
                let mask = self.maskForRequest(VNGenerateForegroundInstanceMaskRequest(), from: inImage)
            {
                self.outputTexturePort.send(try renderer.newImage(fromPixelBuffer: mask))
            }
        }
    }
    
    private func maskForRequest(_ request: VNGenerateForegroundInstanceMaskRequest, from image: FabricImage) -> CVPixelBuffer?
    {
        if let inputImage = image.presentationCIImage
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
                    let mask = try observation.generateMask(forInstances: observation.allInstances)
  
                    return mask
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
