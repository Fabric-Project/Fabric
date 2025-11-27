
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

public class SyphonClientNode : Node
{
    public override class var name:String { "Syphon Client" }
    public override class var nodeType:Node.NodeType { Node.NodeType.Image(imageType: .Loader) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Connect to a Syphon Server, providing an stream of output Images"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputServerID", ParameterPort(parameter: StringParameter("Syphon Server", "", .inputfield))),
            ("outputTexturePort", NodePort<EquatableTexture>(name: "Image", kind: .Outlet)),
        ]
    }

    public var inputFilePathParam:ParameterPort<String>  { port(named: "inputFilePathParam") }
    public var outputTexturePort:NodePort<EquatableTexture> { port(named: "outputTexturePort") }

    @ObservationIgnored private var syphonClient:SyphonMetalClient? = nil
    @ObservationIgnored private var texture: (any MTLTexture)? = nil
    
    public required init(context:Context)
    {
        super.init(context: context)
//        self.syphonClient = SyphonMetalClient(serverDescription: <#T##[String : Any]#>)
    }
    
    
    public required init(from decoder: any Decoder) throws
    {
        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }
        

        try super.init(from:decoder)
    }
    
    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if self.inputFilePathParam.valueDidChange
        {
            
            if let texture = self.texture
            {
                self.outputTexturePort.send(EquatableTexture(texture: texture))
            }
            
            else
            {
                self.outputTexturePort.send(nil)
            }
        }
     }

}
