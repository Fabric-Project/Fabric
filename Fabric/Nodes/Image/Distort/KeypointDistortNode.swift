//
//  KeypointDistortNode.swift
//  Fabric
//
//  Created by Anton Marini on 11/1/25.
//

import Foundation

import Foundation
import Metal
import Satin
import simd

public class KeypointDistortNode: BaseEffectNode {
    // MARK: - UI & Type
    override public class var name: String { "Key Point Displacement" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .Distort) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Uses a pair of Reference Keypoints and Displaced Keypoints to Distort the Image." }
 
    class override var sourceShaderName:String { "KeypointDistortShader" }
    
    // MARK: - Ports (Registry)
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputReferenceKeyPoints", NodePort<ContiguousArray<simd_float2>>(name: "Reference Key Points", kind: .Inlet)),

            ("inputDisplacedKeyPoints", NodePort<ContiguousArray<simd_float2>>(name: "Displaced Key Points", kind: .Inlet)),
        ]
    }

    // Proxies
    public var inputReferenceKeyPoints:  NodePort<ContiguousArray<simd_float2>> { port(named: "inputReferenceKeyPoints") }
    public var inputDisplacedKeyPoints:  NodePort<ContiguousArray<simd_float2>> { port(named: "inputDisplacedKeyPoints") }

    
    private var refKeyPointStructBuffer:StructBuffer<simd_float2>!
    private var disKeyPointStructBuffer:StructBuffer<simd_float2>!
    private var countBuffer:StructBuffer<UInt32>!

    required init(context: Context, fileURL: URL) throws {
        try super.init(context: context, fileURL: fileURL)
        self.postInit()
    }
    
    required init(context: Context) {
        super.init(context: context)
        self.postInit()
    }
    
    required init(from decoder: any Decoder) throws {
        try super.init(from: decoder)
        self.postInit()
    }
    
    private func postInit()
    {
        self.refKeyPointStructBuffer = StructBuffer<simd_float2>(device: context.device, count: 1, label: "Reference Keypoint Struct Buffer")
        self.disKeyPointStructBuffer = StructBuffer<simd_float2>(device: context.device, count: 1, label: "Displacement Keypoint Struct Buffer")
        self.countBuffer = StructBuffer<UInt32>(device: context.device, count: 1, label: "Count Struct Buffer")

        self.refKeyPointStructBuffer.update(data: [.zero])
        self.disKeyPointStructBuffer.update(data: [.zero])
        self.countBuffer.update(data: [UInt32(0)])
    }
    
    override public func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard let graphRenderer = context.graphRenderer,
              let device = graphRenderer.device
        else { return }
        
        
        // If counts are diff, update backing
        if self.inputReferenceKeyPoints.valueDidChange,
           let inputReferenceKeyPoints = self.inputReferenceKeyPoints.value
        {
            if self.refKeyPointStructBuffer.count != inputReferenceKeyPoints.count {
                
                self.refKeyPointStructBuffer = StructBuffer<simd_float2>(device: device,
                                                                         count: inputReferenceKeyPoints.count,
                                                                         label: "Reference Keypoint Struct Buffer")
            }
            
            self.refKeyPointStructBuffer.update(data: inputReferenceKeyPoints)
        }
         
        // If counts are diff, update backing
        if self.inputDisplacedKeyPoints.valueDidChange,
           let inputDisplacedKeyPoints = self.inputDisplacedKeyPoints.value
        {
            if self.disKeyPointStructBuffer.count != inputDisplacedKeyPoints.count
            {
                self.disKeyPointStructBuffer = StructBuffer<simd_float2>(device: device,
                                                                         count: inputDisplacedKeyPoints.count,
                                                                         label: "Displacement Keypoint Struct Buffer")
            }
            
            self.disKeyPointStructBuffer.update(data: inputDisplacedKeyPoints)
        }
        
        if self.inputTexturePort.valueDidChange
        {
            if let inTex = self.inputTexturePort.value?.texture,
               let outImage = context.graphRenderer?.newImage(withWidth: inTex.width, height: inTex.height)
            {
                let minCount = min (self.refKeyPointStructBuffer.count, self.disKeyPointStructBuffer.count)
                self.countBuffer.update(data: [UInt32(minCount)] )
                
                self.postMaterial.set(self.refKeyPointStructBuffer, index: FragmentBufferIndex.Custom0)
                self.postMaterial.set(self.disKeyPointStructBuffer, index: FragmentBufferIndex.Custom1)
                self.postMaterial.set(self.countBuffer, index: FragmentBufferIndex.Custom2)
                
                self.postMaterial.set(inTex, index: FragmentTextureIndex.Custom0)

                    
                self.postProcessor.renderer.size.width = Float(inTex.width)
                self.postProcessor.renderer.size.height = Float(inTex.height)
                
                let renderPassDesc = MTLRenderPassDescriptor()
                renderPassDesc.colorAttachments[0].texture = outImage.texture
                
                self.postProcessor.draw(renderPassDescriptor:renderPassDesc , commandBuffer: commandBuffer)

                self.outputTexturePort.send( outImage )
            }
            else
            {
                self.outputTexturePort.send( nil )
            }
        }

        
    }
}
