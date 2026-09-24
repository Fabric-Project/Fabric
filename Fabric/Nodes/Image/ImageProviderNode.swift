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
import CoreGraphics
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

    private var image: FabricImage? = nil
    private var textureLoader:MTKTextureLoader
    private var url: URL? = nil
    
    public func setFileURL(_ url: URL) {
        self.inputFilePathParam.value = url.standardizedFileURL.absoluteString
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

        try self.loadTextureFromInputValue()
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if self.inputFilePathParam.valueDidChange
        {
            try self.loadTextureFromInputValue()
            
            self.outputTexturePort.send(self.image)
        }
     }
    
    private func loadTextureFromInputValue() throws
    {
        if let path = self.inputFilePathParam.value,
           path.isEmpty == false && self.url != URL(string: path)
        {
            guard let url = URL(string: path) else
            {
                throw FabricError(.execution(.fileNotFound),
                                  severity: .recoverable,
                                  message: "Image file path is invalid: \(path)")
            }

            self.url = url

            guard FileManager.default.fileExists(atPath: url.standardizedFileURL.path(percentEncoded: false)) else
            {
                self.image = nil
                throw FabricError(.execution(.fileNotFound),
                                  severity: .recoverable,
                                  message: "Image file not found: \(url.path)")
            }

            do
            {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else
                {
                    throw FabricError(.execution(.failed),
                                      severity: .recoverable,
                                      message: "Could not decode image file: \(url.path)")
                }

                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                let orientationValue = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
                let orientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up

                // Map presentation UVs back to stored CGImage UVs. Both use
                // Fabric/Satin/Metal's top-left origin; translations keep the
                // rotated or mirrored coordinates within the unit square.
                let samplingTransform: CGAffineTransform
                switch orientation
                {
                case .up:
                    samplingTransform = .identity
                case .upMirrored:
                    samplingTransform = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 1, ty: 0)
                case .down:
                    samplingTransform = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1, ty: 1)
                case .downMirrored:
                    samplingTransform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 1)
                case .leftMirrored:
                    samplingTransform = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
                case .right:
                    samplingTransform = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 1)
                case .rightMirrored:
                    samplingTransform = CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: 1, ty: 1)
                case .left:
                    samplingTransform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0)
                @unknown default:
                    samplingTransform = .identity
                }

                // Load the un-oriented CGImage pixels so metadata is applied
                // exactly once, through FabricImage's sampling transform.
                let texture = try self.textureLoader.newTexture(cgImage: sourceImage, options: [
                    .generateMipmaps : true,
                    .allocateMipmaps : true,
                    .textureStorageMode : NSNumber( value: MTLStorageMode.shared.rawValue),
                    .SRGB : false,
                    .origin: MTKTextureLoader.Origin.topLeft,
                ])
                let image = FabricImage.unmanaged(texture: texture)
                // SIMD matrices store columns: X basis, Y basis, Z basis, translation.
                image.textureTransform = simd_float4x4(
                    simd_float4(Float(samplingTransform.a), Float(samplingTransform.b), 0, 0),
                    simd_float4(Float(samplingTransform.c), Float(samplingTransform.d), 0, 0),
                    simd_float4(0, 0, 1, 0),
                    simd_float4(Float(samplingTransform.tx), Float(samplingTransform.ty), 0, 1))
                self.image = image
            }
            catch
            {
                self.image = nil
                throw FabricError(.execution(.failed),
                                  severity: .recoverable,
                                  message: "Could not load image file: \(url.path)",
                                  underlyingError: error)
            }
        }
    }
}
