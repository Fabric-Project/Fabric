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

class BaseEffectThreeChannelNode: Node, NodeFileLoadingProtocol
{
    override class var name:String { "Base Effect" }
    override class var nodeType:Node.NodeType { .Image(imageType: .BaseEffect) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }

    override var name: String {
        guard let fileURL = self.url else {
            return BaseEffectNode.name
        }
        
        return self.fileURLToName(fileURL: fileURL)
    }
    
    class var sourceShaderName:String { "" }

    open class PostMaterial: SourceMaterial {}

    let postMaterial:PostMaterial
    let postProcessor:PostProcessor
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputTexturePort", NodePort<EquatableTexture>(name: "Image 1", kind: .Inlet)),
            ("inputTexture2Port", NodePort<EquatableTexture>(name: "Image 2", kind: .Inlet)),
            ("inputTexture3Port", NodePort<EquatableTexture>(name: "Image 2", kind: .Inlet)),
            ("outputTexturePort", NodePort<EquatableTexture>(name: "Image", kind: .Outlet)),
        ]
    }

    public var inputTexturePort:NodePort<EquatableTexture>  { port(named: "inputTexturePort") }
    public var inputTexture2Port:NodePort<EquatableTexture> { port(named: "inputTexture2Port") }
    public var inputTexture3Port:NodePort<EquatableTexture> { port(named: "inputTexture3Port") }
    public var outputTexturePort:NodePort<EquatableTexture> { port(named: "outputTexturePort") }
    
    private var url:URL? = nil
    
    required init(context: Satin.Context, fileURL: URL) throws
    {
        self.url = fileURL
        let material = PostMaterial(pipelineURL:fileURL)
        material.context = context

        self.postMaterial = material
        self.postProcessor = PostProcessor(context: context,
                                           material: material,
                                           frameBufferOnly: false)
                
        super.init(context: context)
        
        for param in self.postMaterial.parameters.params {

            if let p = PortType.portForType(from:param)
            {
                self.addDynamicPort(p)
            }
        }
    }
    
    required init(context:Context)
    {
        let bundle = Bundle(for: Self.self)
        let shaderURL = bundle.url(forResource: Self.sourceShaderName, withExtension: "metal", subdirectory: "Shaders")
        
        
        let material = PostMaterial(pipelineURL:shaderURL!)
        material.context = context

        self.postMaterial = material
        self.postProcessor = PostProcessor(context: context,
                                           material: material,
                                           frameBufferOnly: false)
                
        super.init(context: context)
        
        for param in self.postMaterial.parameters.params {

            if let p = PortType.portForType(from:param)
            {
                self.addDynamicPort(p)
            }
        }
    }
    
    enum CodingKeys : String, CodingKey
    {
        // Store the last 2 directory components (effects/subfolder) within the bundle
        case effectPath
    }
    
    override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
                
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
        
        if let path = try container.decodeIfPresent(String.self, forKey: .effectPath)
        {
            let bundle = Bundle(for: Self.self)
            if let shaderURL = bundle.resourceURL?.appendingPathComponent(path)
            {
                self.url = shaderURL
                
                let material = PostMaterial(pipelineURL:shaderURL)
                material.context = decodeContext.documentContext

                self.postMaterial = material
                self.postProcessor = PostProcessor(context: decodeContext.documentContext,
                                                   material: material,
                                                   frameBufferOnly: false)
            }
            else
            {
                let bundle = Bundle(for: Self.self)
                let shaderURL = bundle.url(forResource: Self.sourceShaderName, withExtension: "metal", subdirectory: "Shaders")
                
                let material = PostMaterial(pipelineURL:shaderURL!)
                material.context = decodeContext.documentContext

                self.postMaterial = material
                self.postProcessor = PostProcessor(context: decodeContext.documentContext,
                                                   material: material,
                                                   frameBufferOnly: false)
            }
        }
        else
        {
            let bundle = Bundle(for: Self.self)
            let shaderURL = bundle.url(forResource: Self.sourceShaderName, withExtension: "metal", subdirectory: "Shaders")
            
            let material = PostMaterial(pipelineURL:shaderURL!)
            material.context = decodeContext.documentContext

            self.postMaterial = material
            self.postProcessor = PostProcessor(context: decodeContext.documentContext,
                                               material: material,
                                               frameBufferOnly: false)
        }
        
        try super.init(from:decoder)
        
        // Assign our deserialized param and map to materials new group
        for param in self.postMaterial.parameters.params {

            for port in self.ports
            {
                if port.name == param.label
                {
                    port.parameter = param
                }
            }
        }
    }
    
    override func execute(context:GraphExecutionContext,
                          renderPassDescriptor: MTLRenderPassDescriptor,
                          commandBuffer: MTLCommandBuffer)
    {
        let anyPortChanged =  self.ports.reduce(false, { partialResult, next in
           return partialResult || next.valueDidChange
        })
        
        if  self.inputTexturePort.valueDidChange || self.inputTexture2Port.valueDidChange || self.inputTexture3Port.valueDidChange || anyPortChanged || self.isDirty
        {
            if let inTex = self.inputTexturePort.value?.texture,
               let inTex2 = self.inputTexture2Port.value?.texture,
               let inTex3 = self.inputTexture3Port.value?.texture
            {
                self.postProcessor.mesh.preDraw = { renderEncoder in
                    
                    renderEncoder.setFragmentTexture(inTex, index: FragmentTextureIndex.Custom0.rawValue)
                    renderEncoder.setFragmentTexture(inTex2, index: FragmentTextureIndex.Custom1.rawValue)
                    renderEncoder.setFragmentTexture(inTex3, index: FragmentTextureIndex.Custom2.rawValue)
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
