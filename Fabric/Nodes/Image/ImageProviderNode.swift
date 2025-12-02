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

public class ImageProviderNode : Node
{
    public override class var name:String { "Image Provider" }
    public override class var nodeType:Node.NodeType { Node.NodeType.Image(imageType: .Loader) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Load an image file from disk, providing an output Image"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputFilePathParam", ParameterPort(parameter: StringParameter("File Path", "", .filepicker))),
            ("outputTexturePort", NodePort<EquatableTexture>(name: "Image", kind: .Outlet)),
        ]
    }

    public var inputFilePathParam:ParameterPort<String>  { port(named: "inputFilePathParam") }
    public var outputTexturePort:NodePort<EquatableTexture> { port(named: "outputTexturePort") }

    @ObservationIgnored private var texture: (any MTLTexture)? = nil
    @ObservationIgnored private var textureLoader:MTKTextureLoader
    @ObservationIgnored private var url: URL? = nil
    
    public required init(context:Context)
    {
        self.textureLoader = MTKTextureLoader(device: context.device)

        super.init(context: context)
  
        self.loadTextureFromInputValue()
    }
    
    
    public required init(from decoder: any Decoder) throws
    {
        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }
        
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
        if let path = self.inputFilePathParam.value,
           path.isEmpty == false && self.url != URL(string: path)
        {
            self.url = URL(string: path)

            if FileManager.default.fileExists(atPath: self.url!.standardizedFileURL.path(percentEncoded: false) )
            {
                
                self.texture = try! self.textureLoader.newTexture(URL: self.url!, options: [
                    .generateMipmaps : true,
                    .allocateMipmaps : true,
                    .textureStorageMode : NSNumber( value: MTLStorageMode.shared.rawValue),
                    .SRGB : true,
                    .origin: MTKTextureLoader.Origin.topLeft,
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
