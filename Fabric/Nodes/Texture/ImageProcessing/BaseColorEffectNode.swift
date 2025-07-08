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

class BaseColorEffectNode : Node, NodeProtocol
{
    class var name:String { "Base Texture Compute" }
    class var nodeType:Node.NodeType { .Texture }
    class var sourceShaderName:String { "" }

    open class PostMaterial: SourceMaterial {}

    let postMaterial:PostMaterial
    let postProcessor:PostProcessor
    
    // Parameters
    override var inputParameters: [any Parameter] { super.inputParameters  + self.postMaterial.parameters.params }

    // Ports
    let inputTexturePort:NodePort<EquatableTexture>
    let outputTexturePort:NodePort<EquatableTexture>
    override var ports: [any NodePortProtocol] { super.ports + [inputTexturePort, outputTexturePort] }

    
    required init(context:Context)
    {
        self.inputTexturePort = NodePort<EquatableTexture>(name: "Texture", kind: .Inlet)
        self.outputTexturePort = NodePort<EquatableTexture>(name: "Texture", kind: .Outlet)

        let bundle = Bundle(for: Self.self)
        let shaderURL = bundle.url(forResource: Self.sourceShaderName, withExtension: "metal", subdirectory: "Shaders")
        
        let material = PostMaterial(pipelineURL:shaderURL!)
        material.setup()
        
        self.postMaterial = material
        self.postProcessor = PostProcessor(context: context,
                                           material: material,
                                           frameBufferOnly: false)
        
        self.postProcessor.renderer.colorTextureStorageMode = .private
        
        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputTexturePort
        case outputTexturePort
    }
    
    override func encode(to encoder:Encoder) throws
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

        let bundle = Bundle(for: Self.self)
        let shaderURL = bundle.url(forResource: Self.sourceShaderName, withExtension: "metal", subdirectory: "Shaders")
        
        let material = PostMaterial(pipelineURL:shaderURL!)
        material.setup()

        self.postMaterial = material
        self.postProcessor = PostProcessor(context: decodeContext.documentContext,
                                           material: material,
                                           frameBufferOnly: false)
        
        try super.init(from:decoder)
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
            
            self.postProcessor.draw(renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commandBuffer)
            
            if let outTex = self.postProcessor.renderer.colorTexture
            {
                let outputTexture = EquatableTexture(texture: outTex)
                self.outputTexturePort.send( outputTexture )
            }
        }
        else
        {
            self.outputTexturePort.send( nil )
        }

    }
    
//    override func execute(context:GraphExecutionContext,
//                          renderPassDescriptor: MTLRenderPassDescriptor,
//                          commandBuffer: MTLCommandBuffer)
//    {
//        
//        if let texture = self.texture
//        {
//            self.outputTexturePort.send( EquatableTexture(texture: texture) )
//        }
//        else
//        {
//            self.outputTexturePort.send( nil )
//        }
//    }
}
