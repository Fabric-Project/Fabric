
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
            ("inputServerName", ParameterPort(parameter: StringParameter("Server Name", "", [String](), .inputfield, "Name of the Syphon server to connect to"))),
            ("inputServerAppName", ParameterPort(parameter: StringParameter("Application Name", "", [String](), .inputfield, "Name of the application hosting the Syphon server"))),
            ("outputTexturePort", NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "Received Syphon frame")),
        ]
    }

    public var inputServerName:ParameterPort<String>  { port(named: "inputServerName") }
    public var inputServerAppName:ParameterPort<String>  { port(named: "inputServerAppName") }
    public var outputTexturePort:NodePort<FabricImage> { port(named: "outputTexturePort") }

    @ObservationIgnored private var syphonClient:SyphonMetalClient? = nil
    @ObservationIgnored private var texture: (any MTLTexture)? = nil
    
    
    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if self.inputServerName.valueDidChange || self.inputServerAppName.valueDidChange,
           let inputServerName = self.inputServerName.value,
           let inputServerAppName = self.inputServerAppName.value,
           let device =  context.graphRenderer?.device
        {
            if let firstServerDict = SyphonServerDirectory.shared().servers(matchingName: inputServerName, appName: inputServerAppName).first
            {
                self.syphonClient = SyphonMetalClient(serverDescription: firstServerDict, device:device)
            }
        }
        
        if let syphonClient = self.syphonClient,
           syphonClient.isValid,
           let texture = syphonClient.newFrameImage()
        {
            self.outputTexturePort.send(FabricImage.unmanaged(texture: texture))
        }
        else
        {
            self.outputTexturePort.send(nil)
        }

    }

}
