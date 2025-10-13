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

class BaseEffectNode: Node, NodeFileLoadingProtocol
{
    override class var name:String { "Base Effect" }
    
    override var name: String {
        guard let fileURL = self.url else {
            return BaseEffectNode.name
        }
        
        return self.fileURLToName(fileURL: fileURL)
    }
    
    override class var nodeType:Node.NodeType { .Image(imageType: .BaseEffect) }
    class var sourceShaderName:String { "" }

    open class PostMaterial: SourceMaterial {}

    let postMaterial:PostMaterial
    let postProcessor:PostProcessor
    
    // Parameters
    override var inputParameters: [any Parameter] { self.postMaterial.parameters.params + super.inputParameters }

    // Ports
    let inputTexturePort:NodePort<EquatableTexture>
    let outputTexturePort:NodePort<EquatableTexture>
    override var ports: [any NodePortProtocol] { [inputTexturePort, outputTexturePort] + super.ports}
    
    private var url:URL? = nil
    
    required init(context: Satin.Context, fileURL: URL) throws {
        self.inputTexturePort = NodePort<EquatableTexture>(name: "Image", kind: .Inlet)
        self.outputTexturePort = NodePort<EquatableTexture>(name: "Image", kind: .Outlet)

        self.url = fileURL
        let material = PostMaterial(pipelineURL:fileURL)
        material.setup()
        
        self.postMaterial = material
        self.postProcessor = PostProcessor(context: context,
                                           material: material,
                                           frameBufferOnly: false)
                
        super.init(context: context)
    }
    
    required init(context:Context)
    {
        self.inputTexturePort = NodePort<EquatableTexture>(name: "Image", kind: .Inlet)
        self.outputTexturePort = NodePort<EquatableTexture>(name: "Image", kind: .Outlet)

        let bundle = Bundle(for: Self.self)
        let shaderURL = bundle.url(forResource: Self.sourceShaderName, withExtension: "metal", subdirectory: "Shaders")
        
        
        let material = PostMaterial(pipelineURL:shaderURL!)
        material.setup()
        
        self.postMaterial = material
        self.postProcessor = PostProcessor(context: context,
                                           material: material,
                                           frameBufferOnly: false)
                
        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputTexturePort
        case outputTexturePort
        
        // Store the last 2 directory components (effects/subfolder) within the bundle
        case effectPath
        
    }
    
    override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputTexturePort, forKey: .inputTexturePort)
        try container.encode(self.outputTexturePort, forKey: .outputTexturePort)
        
        if let url = self.url
        {
            let last2 = url.pathComponents.suffix(3)
            
            let path = last2.joined(separator: "/")
            
            try container.encode(path, forKey: .effectPath)
        }

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

        if let path = try container.decodeIfPresent(String.self, forKey: .effectPath)
        {
            let bundle = Bundle(for: Self.self)
            if let shaderURL = bundle.resourceURL?.appendingPathComponent(path)
            {
                self.url = shaderURL
                
                let material = PostMaterial(pipelineURL:shaderURL)
                material.setup()
                
                self.postMaterial = material
                self.postProcessor = PostProcessor(context: decodeContext.documentContext,
                                                   material: material,
                                                   frameBufferOnly: false)
            }
            else
            {
                let bundle = Bundle(for: Self.self)
                let shaderURL = bundle.url(forResource: Self.sourceShaderName, withExtension: "metal", subdirectory: "Materials")
                
                let material = PostMaterial(pipelineURL:shaderURL!)
                material.setup()

                self.postMaterial = material
                self.postProcessor = PostProcessor(context: decodeContext.documentContext,
                                                   material: material,
                                                   frameBufferOnly: false)
            }
        }
        else
        {
            let bundle = Bundle(for: Self.self)
            let shaderURL = bundle.url(forResource: Self.sourceShaderName, withExtension: "metal", subdirectory: "Materials")
            
            let material = PostMaterial(pipelineURL:shaderURL!)
            material.setup()

            self.postMaterial = material
            self.postProcessor = PostProcessor(context: decodeContext.documentContext,
                                               material: material,
                                               frameBufferOnly: false)
        }
        
        try super.init(from:decoder)
    }
    
    override func execute(context:GraphExecutionContext,
                          renderPassDescriptor: MTLRenderPassDescriptor,
                          commandBuffer: MTLCommandBuffer)
    {
        let anyParamDidChange =  self.inputParameters.reduce(false, { partialResult, next in
           return partialResult || next.valueDidChange
        })

        if self.inputTexturePort.valueDidChange || anyParamDidChange || self.isDirty
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
    }
    
    
    private func fileURLToName(fileURL:URL) -> String {
        let nodeName =  fileURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "ImageNode", with: "")

        return nodeName.titleCase
    }
}
