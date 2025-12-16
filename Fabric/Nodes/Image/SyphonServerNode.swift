
//
//  SyphonProviderNode.swift
//  Fabric
//
//  Created by Anton Marini on 11/27/25.
//

import Foundation
import Satin
import simd
import Metal
import Syphon

public class SyphonServerNode : Node
{
    public override class var name:String { "Syphon Server" }
    public override class var nodeType:Node.NodeType { Node.NodeType.Image(imageType: .Loader) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Send an Image stream out to a Syphon Server"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputServerName", ParameterPort(parameter: StringParameter("Syphon Server", "", .inputfield))),
            ("inputTexture", NodePort<FabricImage>(name: "Image", kind: .Inlet)),
        ]
    }

    public var inputServerName:ParameterPort<String>  { port(named: "inputServerName") }
    public var inputTexture:NodePort<FabricImage> { port(named: "inputTexture") }

    @ObservationIgnored private let syphonServer:SyphonMetalServer
    @ObservationIgnored private var texture: (any MTLTexture)? = nil
    
    public required init(context:Context)
    {
        self.syphonServer = SyphonMetalServer(name: "Fabric", device: context.device, options: nil)
        super.init(context: context)
    }
    
    
    public required init(from decoder: any Decoder) throws
    {
        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }
        
        self.syphonServer = SyphonMetalServer(name: "Fabric", device: decodeContext.documentContext.device, options: nil)
        
        try super.init(from:decoder)
    }
    
    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if self.inputServerName.valueDidChange,
           let name = self.inputServerName.value
        {
            self.syphonServer.name = name
        }
            
        if self.inputTexture.valueDidChange,
           let texture = self.inputTexture.value
        {
            let region = NSRect(origin: .zero, size: .init(width: texture.texture.width, height: texture.texture.height))

            // Somethings up with flippedness?
            self.syphonServer.publishFrameTexture(texture.texture, on: commandBuffer, imageRegion: region, flipped: !texture.isFlipped)
        }
     }
}
