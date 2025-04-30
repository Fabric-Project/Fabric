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

    // Ports
    let inputURL = NodePort<URL>(name: "File URL", kind: .Inlet)
    let outputTexture = NodePort<(any MTLTexture)>(name: "Texture", kind: .Outlet)

    // Parameters
    let inputURLParam = StringParameter("InputParam", "", .dropdown)
    
    override var parameterGroup: ParameterGroup  {
        ParameterGroup("Parameters", [self.inputURLParam])
    }
    
    private var texture: (any MTLTexture)? = nil
    private var url: URL? = nil
    
    override var ports: [any AnyPort] { super.ports + [outputTexture] }
    
    required init(context:Context)
    {
        super.init(context: context)
        
        self.texture = self.loadTexture(device: self.context.device, url: URL(fileURLWithPath: "/Users/vade/Downloads/Contract-Card-09.png") )

    }

    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        if let inputURL = self.inputURL.value
        {
            self.url = inputURL
            
            self.texture = self.loadTexture(device: self.context.device, url: inputURL )
        }
        
        if let texture = self.texture
        {
            self.outputTexture.send(texture)
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
