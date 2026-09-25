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

    private var texture: (any MTLTexture)? = nil
    private var textureLoader:MTKTextureLoader
    private var url: URL? = nil
    
    public func setFileURL(_ url: URL) {
        self.inputFilePathParam.value = DocumentFileReference.reference(for: url, relativeTo: self.graph?.fileReferenceBaseURL)
    }
    
    public required init(context:Context)
    {
        self.textureLoader = MTKTextureLoader(device: context.device)

        super.init(context: context)
  
        try? self.loadTextureFromInputValue()
    }
    
    public required init(context: Satin.Context, fileURL: URL) throws
    {
        self.textureLoader = MTKTextureLoader(device: context.device)
        super.init(context: context)
        self.setFileURL(fileURL)
        try self.loadTextureFromInputValue()
    }
    
    
    public required init(from decoder: any Decoder) throws
    {
        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }

        self.textureLoader = MTKTextureLoader(device: decodeContext.documentContext.device)

        try super.init(from:decoder)

        // External resource availability is runtime state. The hydrated port
        // remains changed so the first execution attempts the load.
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if self.inputFilePathParam.valueDidChange
        {
            self.normalizeFileReference(self.inputFilePathParam)
            try self.loadTextureFromInputValue()
            
            if let texture = self.texture
            {
                self.outputTexturePort.send(FabricImage.unmanaged(texture: texture))
            }
            
            else
            {
                self.outputTexturePort.send(nil)
            }
        }
     }
    
    private func loadTextureFromInputValue() throws
    {
        if let path = self.inputFilePathParam.value,
           path.isEmpty == false
        {
            guard let url = self.graph?.resolveFileReference(path)
                ?? DocumentFileReference.resolve(path, relativeTo: nil) else
            {
                throw FabricError(.execution(.fileNotFound),
                                  severity: .recoverable,
                                  message: "Image file path is invalid: \(path)")
            }

            guard self.url != url else { return }

            self.url = url

            guard FileManager.default.fileExists(atPath: url.standardizedFileURL.path(percentEncoded: false)) else
            {
                self.texture = nil
                throw FabricError(.execution(.fileNotFound),
                                  severity: .recoverable,
                                  message: "Image file not found: \(url.path)")
            }

            do
            {
                self.texture = try self.textureLoader.newTexture(URL: url, options: [
                    .generateMipmaps : true,
                    .allocateMipmaps : true,
                    .textureStorageMode : NSNumber( value: MTLStorageMode.shared.rawValue),
                    .SRGB : true,
                    .origin: MTKTextureLoader.Origin.topLeft,
                ])
            }
            catch
            {
                self.texture = nil
                throw FabricError(.execution(.failed),
                                  severity: .recoverable,
                                  message: "Could not load image file: \(url.path)",
                                  underlyingError: error)
            }

            //.newTexture(url: self.url!, options: [:])
//                self.texture = loadHDR(device: self.context.device, url: self.url! )
        }
    }
}
