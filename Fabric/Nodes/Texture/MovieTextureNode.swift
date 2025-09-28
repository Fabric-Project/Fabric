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
import AVFoundation

class MovieTextureNode : Node, NodeProtocol
{
    static let name = "Movie Player"
    static var nodeType = Node.NodeType.Image(imageType: .Loader)

    // Parameters
    let inputFilePathParam:StringParameter
    override var inputParameters: [any Parameter] { [self.inputFilePathParam] + super.inputParameters}

    // Ports
    let outputTexturePort:NodePort<EquatableTexture>
    override var ports: [any NodePortProtocol] { [outputTexturePort] + super.ports }


    private var texture: (any MTLTexture)? = nil
    
    
    private var url: URL? = nil
    
    required init(context:Context)
    {
        self.inputFilePathParam = StringParameter("File Path", "", .filepicker)
        self.outputTexturePort = NodePort<EquatableTexture>(name: "Texture", kind: .Outlet)

        super.init(context: context)  
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
        
        try super.init(from:decoder)
    }
    
    override func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {

        if let texture = self.texture
        {
            self.outputTexturePort.send( EquatableTexture(texture: texture) )
        }
        else
        {
            self.outputTexturePort.send( nil )
        }
     }

}
