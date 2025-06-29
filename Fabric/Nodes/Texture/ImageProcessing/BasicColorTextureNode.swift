
//
//  BaseTextureComputeNode.swift
//  Fabric
//
//  Created by Anton Marini on 6/28/25.
//

import Foundation
import Satin
import simd
import Metal
import MetalKit

class BasicColorTextureNode : BaseTexturePostProcessNode
{
    override class var name:String { "Base Texture Compute" }
    
    // Parameters

    // Ports
    
    class PostMaterial: SourceMaterial {}

    let postMaterial:PostMaterial
    let postProcessor:PostProcessor

    required init(context:Context)
    {
        let bundle = Bundle(for: Self.self)
        let shaderURL = bundle.url(forResource: "BasicColorTextureNode", withExtension: "metal", subdirectory: "Shaders")
        
        self.postMaterial = PostMaterial(pipelineURL:shaderURL!)
        self.postProcessor = PostProcessor(context: context)
        super.init(context: context)
    }
    
    required init(from decoder: any Decoder) throws {

        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }

        let bundle = Bundle(for: Self.self)
        let shaderURL = bundle.url(forResource: "BasicCOlorTexureNode", withExtension: "metal", subdirectory: "Shaders")
        
        self.postMaterial = PostMaterial(pipelineURL:shaderURL!)
        self.postProcessor = PostProcessor(context: decodeContext.documentContext)

        try super.init(from: decoder)
    }
    
    
    override func execute(context:GraphExecutionContext,
                          renderPassDescriptor: MTLRenderPassDescriptor,
                          commandBuffer: MTLCommandBuffer)
    {
        
        if let inTex = self.inputTexturePort.value?.texture
        {
            self.postProcessor.mesh.preDraw = { renderEncoder in
                
                renderEncoder.setFragmentTexture(inTex, index: FragmentTextureIndex.Custom0.rawValue)
            }
            
            self.postProcessor.renderer.size.width = Float(inTex.width)
            self.postProcessor.renderer.size.height = Float(inTex.height)
            
            self.postProcessor.draw(renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
            
            if let outTex = self.postProcessor.renderer.colorTexture
            {
                let outputTexture = EquatableTexture(texture: outTex)
                self.outputTexturePort.send( outputTexture )
            }
        }
    }
}
