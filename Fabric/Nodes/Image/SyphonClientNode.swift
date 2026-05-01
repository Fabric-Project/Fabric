//
//  SyphonProviderNode.swift
//  Fabric
//
//  Created by Anton Marini on 11/27/25.
//

#if FABRIC_SYPHON_ENABLED

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

    @ObservationIgnored private var syphonClient: SyphonMetalClient? = nil
    @ObservationIgnored private var texture: (any MTLTexture)? = nil
    @ObservationIgnored private var connectedServerName: String = ""
    @ObservationIgnored private var connectedAppName: String = ""

    override public func execute(context: GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        let desiredServer = self.inputServerName.value ?? ""
        let desiredApp = self.inputServerAppName.value ?? ""

        // State-driven: reconcile desired vs connected server each frame.
        // Only update connectedServerName/connectedAppName when the
        // connection is actually established (or intentionally cleared).
        // If the server isn't discovered yet, leave the connected state
        // unchanged so the condition re-fires next frame and retries.
        if desiredServer != connectedServerName || desiredApp != connectedAppName {
            if desiredServer.isEmpty {
                // No server selected — disconnect
                self.syphonClient = nil
                self.texture = nil
                connectedServerName = desiredServer
                connectedAppName = desiredApp
            } else if let device = context.graphRenderer?.device,
                      let serverDict = SyphonServerDirectory.shared()
                          .servers(matchingName: desiredServer, appName: desiredApp).first
            {
                self.syphonClient = SyphonMetalClient(serverDescription: serverDict, device: device)
                self.texture = nil
                connectedServerName = desiredServer
                connectedAppName = desiredApp
            }
            // else: server not yet discovered — retry next frame
        }

        // Read frames, retaining the last valid texture between new frames
        if let syphonClient = self.syphonClient, syphonClient.isValid {
            if let newTexture = syphonClient.newFrameImage() {
                self.texture = newTexture
            }
            if let texture = self.texture {
                var image = FabricImage.unmanaged(texture: texture)
                // Syphon textures originate from OpenGL (origin at bottom-left),
                // so they're vertically inverted relative to Metal's top-left
                // convention. Mark as flipped so downstream nodes (e.g.
                // BasicTextureMaterialNode) skip their default UV Y-flip.
                image.isFlipped = true
                self.outputTexturePort.send(image)
            } else {
                self.outputTexturePort.send(nil)
            }
        } else {
            self.texture = nil
            self.outputTexturePort.send(nil)
        }
    }

}

#endif // FABRIC_SYPHON_ENABLED
