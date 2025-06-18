//
//  LoadTextureNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//

import Foundation
import CoreGraphics
import Satin
import simd
import Metal
import ImageIO

class LoadTextureNode : Node, NodeProtocol
{
    static let name = "Texture Loader"
    static var nodeType = Node.NodeType.Texture

    // Parameters
    let inputFilePathParam:StringParameter
    override var inputParameters: [any Parameter] { super.inputParameters + [self.inputFilePathParam]}

    // Ports
    let outputTexturePort:NodePort<EquatableTexture>
    override var ports: [any NodePortProtocol] { super.ports + [outputTexturePort] }

    private var texture: (any MTLTexture)? = nil
    private var url: URL? = nil
    
    required init(context:Context)
    {
        self.inputFilePathParam = StringParameter("File Path", "", .filepicker)
        self.outputTexturePort = NodePort<EquatableTexture>(name: "Texture", kind: .Outlet)

        super.init(context: context)
        
        self.texture = self.loadTexture(device: self.context.device, url: URL(fileURLWithPath: "/Users/vade/Downloads/Contract-Card-09.png") )
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

        self.inputFilePathParam = try container.decode(StringParameter.self, forKey: .inputFilePathParameter)
        self.outputTexturePort = try container.decode(NodePort<EquatableTexture>.self, forKey: .outputTexturePort)

        try super.init(from:decoder)
        
        self.loadTextureFromInputValue()
    }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        
        self.loadTextureFromInputValue()

        if let texture = self.texture
        {
            self.outputTexturePort.send(EquatableTexture(texture: texture))
        }
     }
    
    
    private func loadTextureFromInputValue()
    {
        if  self.inputFilePathParam.value.isEmpty == false
        {
            self.url = URL(string: self.inputFilePathParam.value)
            
            if FileManager.default.fileExists(atPath: self.url!.standardizedFileURL.path(percentEncoded: false) )
            {
                self.texture = self.loadTexture(device: self.context.device, url: self.url! )
            }
            else
            {
                print("wtf")
            }
        }
    }
    
    func loadTexture(device: MTLDevice, url: URL) -> MTLTexture? {
        let cfURLString = url.path as CFString
        guard let cfURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, cfURLString, CFURLPathStyle.cfurlposixPathStyle, false) else {
            fatalError("Failed to create CFURL from: \(url.path)")
        }
        guard let cgImageSource = CGImageSourceCreateWithURL(cfURL, nil) else {
            fatalError("Failed to create CGImageSource")
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(cgImageSource, 0, nil) else {
            fatalError("Failed to create CGImage")
        }
        
        //    print(cgImage.width)
        //    print(cgImage.height)
        //    print(cgImage.bitsPerComponent)
        //    print(cgImage.bytesPerRow)
        //    print(cgImage.byteOrderInfo)
        
        guard let colorSpace = CGColorSpace(name: CGColorSpace.linearSRGB) else { return nil }
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue //| CGBitmapInfo.floatComponents.rawValue | CGImageByteOrderInfo.order16Little.rawValue
        guard let bitmapContext = CGContext(data: nil,
                                            width: cgImage.width,
                                            height: cgImage.height,
                                            bitsPerComponent: cgImage.bitsPerComponent,
                                            bytesPerRow: cgImage.width * 4,
                                            space: colorSpace,
                                            bitmapInfo: bitmapInfo) else { return nil }
        
        bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        
        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = .bgra8Unorm
        descriptor.width = cgImage.width
        descriptor.height = cgImage.height
        descriptor.depth = 1
        descriptor.usage = .shaderRead
#if os(macOS)
        descriptor.resourceOptions = .storageModeManaged
#elseif os(iOS) || os(tvOS)
        descriptor.resourceOptions = .storageModeShared
#endif
        descriptor.sampleCount = 1
        descriptor.textureType = .type2D
        
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, cgImage.width, cgImage.height), mipmapLevel: 0, withBytes: bitmapContext.data!, bytesPerRow: cgImage.width * 4)
        
        return texture
    }
}
