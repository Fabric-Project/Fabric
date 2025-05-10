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

class HDRTextureNode : Node, NodeProtocol
{
    static let name = "HDR Texture"
    static var nodeType = Node.NodeType.Texture

    // Ports
    let inputURL = NodePort<URL>(name: "File URL", kind: .Inlet)
    let outputTexture = NodePort<EquatableTexture>(name: "Texture", kind: .Outlet)

    private var texture: (any MTLTexture)? = nil
    private var url: URL? = nil
    
    override var ports: [any AnyPort] { [inputURL, outputTexture] }
    
    required init(context:Context)
    {
        super.init(context: context)
        
        self.texture = loadHDR(device: context.device, url: URL(fileURLWithPath: "/Users/vade/Library/Developer/Xcode/DerivedData/Fabric-dnhnuqgtaddjmfddawsitzbzeuqr/SourcePackages/checkouts/Satin/Example/Assets/Shared/Textures/brown_photostudio_02_2k.hdr") )
    }
    
    required init(from decoder: any Decoder) throws
    {
        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }
                    
        try super.init(from:decoder)
    }

    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        if let inputURL = self.inputURL.value
        {
            self.url = inputURL
            
            self.texture = loadHDR(device: commandBuffer.device, url: self.url!)
        }
        
        if let texture = self.texture
        {
            self.outputTexture.send( EquatableTexture(texture: texture) )
        }
     }
}
