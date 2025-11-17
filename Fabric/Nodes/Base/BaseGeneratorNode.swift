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

class BaseGeneratorNode: Node, NodeFileLoadingProtocol
{
    override class var name:String { "Base Image Generator" }
    override class var nodeType:Node.NodeType { .Image(imageType: .Generator) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
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
            ("inputWidth", ParameterPort(parameter: IntParameter("Width", 512, 1, 8192, .inputfield))),
            ("inputHeight", ParameterPort(parameter: IntParameter("Height", 512, 1, 8192, .inputfield))),
            ("outputTexturePort", NodePort<EquatableTexture>(name: "Image", kind: .Outlet)),
        ]
    }

    public var inputWidth:ParameterPort<Int>  { port(named: "inputWidth") }
    public var inputHeight:ParameterPort<Int>  { port(named: "inputHeight") }
    public var outputTexturePort:NodePort<EquatableTexture> { port(named: "outputTexturePort") }
    
    private var url:URL? = nil
    
    required init(context: Satin.Context, fileURL: URL) throws {

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
                let shaderURL = bundle.url(forResource: Self.sourceShaderName, withExtension: "metal", subdirectory: "Materials")
                
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
            let shaderURL = bundle.url(forResource: Self.sourceShaderName, withExtension: "metal", subdirectory: "Materials")
            
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
                    self.replaceParameterOfPort(port, withParam: param)
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

        if self.inputWidth.valueDidChange,
           let width = self.inputWidth.value
        {
            self.postProcessor.renderer.size.width = Float(max(1, width) )
        }
        
        if self.inputHeight.valueDidChange,
           let height = self.inputHeight.value
        {
            self.postProcessor.renderer.size.height = Float( max(1, height) )

        }
        
        self.postProcessor.draw(renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commandBuffer)
        
        if let outTex = self.postProcessor.renderer.colorTexture
        {
            let outputTexture = EquatableTexture(texture: outTex)
            self.outputTexturePort.send( outputTexture )
        }
    }
    
    
    private func fileURLToName(fileURL:URL) -> String {
        let nodeName =  fileURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "ImageNode", with: "")

        return nodeName.titleCase
    }
}
