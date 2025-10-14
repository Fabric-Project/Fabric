//
//  HDRTextureNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//

import Foundation
import Satin
import simd
import Metal
import MetalKit

public class HDRTextureNode : Node
{
    public override var name:String { "HDR Texture" }
    public override var nodeType:Node.NodeType { Node.NodeType.Image(imageType: .Loader) }

    // Parameters
    let inputFilePathParam:StringParameter
    override public var inputParameters: [any Parameter] { [self.inputFilePathParam] + super.inputParameters}

    // Ports
    let outputTexturePort:NodePort<EquatableTexture>
    override public var ports:[AnyPort] {  [outputTexturePort] + super.ports}


    private var texture: (any MTLTexture)? = nil
    private var textureLoader:MTKTextureLoader
    private var url: URL? = nil
    
    public required init(context:Context)
    {
        self.inputFilePathParam = StringParameter("File Path", "", .filepicker)
        self.outputTexturePort = NodePort<EquatableTexture>(name: "Image", kind: .Outlet)

        self.textureLoader = MTKTextureLoader(device: context.device)

        super.init(context: context)
  
        self.loadTextureFromInputValue()
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputFilePathParameter
        case outputTexturePort
    }
    
    override public func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputFilePathParam, forKey: .inputFilePathParameter)
        try container.encode(self.outputTexturePort, forKey: .outputTexturePort)

        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
       
        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }
        
        self.inputFilePathParam = try container.decode(StringParameter.self, forKey: .inputFilePathParameter)
        self.outputTexturePort = try container.decode(NodePort<EquatableTexture>.self, forKey: .outputTexturePort)

        self.textureLoader = MTKTextureLoader(device: decodeContext.documentContext.device)

        try super.init(from:decoder)
        
        self.loadTextureFromInputValue()

    }
    
    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if self.inputFilePathParam.valueDidChange
        {
            self.loadTextureFromInputValue()
            
        }
            if let texture = self.texture
            {
                self.outputTexturePort.send(EquatableTexture(texture: texture))
            }
            
            else
            {
                self.outputTexturePort.send(nil)
            }
        
     }
    
    private func loadTextureFromInputValue()
    {
        if  self.inputFilePathParam.value.isEmpty == false && self.url != URL(string: self.inputFilePathParam.value)
        {
            self.url = URL(string: self.inputFilePathParam.value)
            
            if FileManager.default.fileExists(atPath: self.url!.standardizedFileURL.path(percentEncoded: false) )
            {
                
                self.texture = try! self.textureLoader.newTexture(URL: self.url!, options: [
                    .generateMipmaps : true,
                    .allocateMipmaps : true,
                    .textureStorageMode : NSNumber( value: MTLStorageMode.shared.rawValue),
                    .SRGB : true,
//                    .origin: MTKTextureLoader.Origin.flippedVertically,
                ])
                    
                    //.newTexture(url: self.url!, options: [:])
//                self.texture = loadHDR(device: self.context.device, url: self.url! )
            }
            else
            {
                self.texture = nil
                print("wtf")
            }
        }
    }
}
