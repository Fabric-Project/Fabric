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
import ImageIO
import UniformTypeIdentifiers

public class ImageProviderNode : Node, NodeFileLoadingProtocol
{
    public static var supportedContentTypes: [UTType] {
        (CGImageSourceCopyTypeIdentifiers() as! [String]).compactMap { UTType($0) }
    }

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
            ("inputFilePathParam", ParameterPort(parameter: StringParameter("File Path", "", .filepicker, "Path to the image file to load"))),
            ("outputTexturePort", NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "The loaded image")),
        ]
    }

    public var inputFilePathParam:ParameterPort<String>  { port(named: "inputFilePathParam") }
    public var outputTexturePort:NodePort<FabricImage> { port(named: "outputTexturePort") }

    @ObservationIgnored private var texture: (any MTLTexture)? = nil
    @ObservationIgnored private var textureLoader:MTKTextureLoader
    @ObservationIgnored private var url: URL? = nil
    
    public func setFileURL(_ url: URL) {
        self.inputFilePathParam.value = url.standardizedFileURL.absoluteString
    }
    
    public required init(context:Context)
    {
        self.textureLoader = MTKTextureLoader(device: context.device)

        super.init(context: context)
  
        self.loadTextureFromInputValue()
    }
    
    public required init(context: Satin.Context, fileURL: URL) throws
    {
        self.textureLoader = MTKTextureLoader(device: context.device)
        super.init(context: context)
        self.setFileURL(fileURL)
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

        // Always send the current texture state. The texture is loaded
        // during init (from decoder), but valueDidChange may already be
        // cleared before the first execute, leaving the output port nil.
        if let texture = self.texture
        {
            self.outputTexturePort.send(FabricImage.unmanaged(texture: texture))
        }
        else if self.outputTexturePort.value != nil
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
