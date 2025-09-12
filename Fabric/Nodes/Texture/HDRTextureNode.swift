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

class HDRTextureNode : Node, NodeProtocol
{
    static let name = "HDR Texture"
    static var nodeType = Node.NodeType.Texture

    // Parameters
    let inputFilePathParam:StringParameter
    override var inputParameters: [any Parameter] { [self.inputFilePathParam] + super.inputParameters}

    // Ports
    let outputTexturePort:NodePort<EquatableTexture>
    override var ports: [any NodePortProtocol] {  [outputTexturePort] + super.ports}


    private var texture: (any MTLTexture)? = nil
    private var textureLoader:MTKTextureLoader
    private var url: URL? = nil
    
    required init(context:Context)
    {
        self.inputFilePathParam = StringParameter("File Path", "", .filepicker)
        self.outputTexturePort = NodePort<EquatableTexture>(name: "Texture", kind: .Outlet)

        self.textureLoader = MTKTextureLoader(device: context.device)

        super.init(context: context)
  
        self.loadTextureFromInputValue()
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputFilePathParameter
        case outputTexturePort
    }
    
    override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputFilePathParam, forKey: .inputFilePathParameter)
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
        
        self.inputFilePathParam = try container.decode(StringParameter.self, forKey: .inputFilePathParameter)
        self.outputTexturePort = try container.decode(NodePort<EquatableTexture>.self, forKey: .outputTexturePort)

        self.textureLoader = MTKTextureLoader(device: decodeContext.documentContext.device)

        try super.init(from:decoder)
        
        self.loadTextureFromInputValue()

    }
    
    override func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        //        if let inputFilePath = self.inputFilePathParam.value
//        {
//            self.url = URL(fileURLWithPath: inputFilePath)
//
//            self.texture = self.loadTexture(device: self.context.device, url: inputURL )
//        }
       
        if self.inputFilePathParam.valueDidChange
        {
            self.loadTextureFromInputValue()
        }
        
        if let texture = self.texture
        {
            self.outputTexturePort.send( EquatableTexture(texture: texture) )
        }
        else
        {
            self.outputTexturePort.send( nil )
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
                    .SRGB : false,
                    .origin: MTKTextureLoader.Origin.flippedVertically,
                ])
                    
                    //.newTexture(url: self.url!, options: [:])
//                self.texture = loadHDR(device: self.context.device, url: self.url! )
            }
            else
            {
                print("wtf")
            }
        }
    }
}
