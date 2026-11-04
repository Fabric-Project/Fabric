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
    let inputTexturePort = NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Input image to analyze")
    let outputTexturePort = NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "Foreground object mask")

    override public func declaredPorts() -> [PortDeclaration]
    {
        [
            PortDeclaration(key: "inputImage", port: self.inputTexturePort),
            PortDeclaration(key: "outputTexturePort", port: self.outputTexturePort),
        ] + super.declaredPorts()
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
