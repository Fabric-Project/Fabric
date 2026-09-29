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
            ("inputServerName", ParameterPort(parameter: StringParameter("Syphon Server", "", .inputfield, "Name of the Syphon server to create"))),
            ("inputTexture", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Image to publish via Syphon")),
        ]
    }

    public var inputServerName:ParameterPort<String>  { port(named: "inputServerName") }
    public var inputTexture:NodePort<FabricImage> { port(named: "inputTexture") }

    private var syphonServer: SyphonMetalServer?
    private var needsInitialFrame = false

    override public func startExecution(renderer: GraphRenderer) throws
    {
        // Syphon starts advertising on initialization. A stopped instance cannot
        // restart, so replace the retained instance when execution resumes.
        if self.executionState != .started
        {
            self.syphonServer = SyphonMetalServer(name: self.inputServerName.value ?? "Fabric",
                                                  device: renderer.device,
                                                  options: nil)
            self.needsInitialFrame = true
        }
        try super.startExecution(renderer: renderer)
    }

    override public func stopExecution(renderer: GraphRenderer) throws
    {
        // Retain the stopped object until disable or a subsequent start replaces it.
        self.syphonServer?.stop()
        self.needsInitialFrame = false
        try super.stopExecution(renderer: renderer)
    }

    override public func disableExecution(renderer: GraphRenderer) throws
    {
        // Also safe when disabling directly without a preceding stop.
        self.syphonServer?.stop()
        self.syphonServer = nil
        self.needsInitialFrame = false
        try super.disableExecution(renderer: renderer)
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard self.executionState == .started, let syphonServer = self.syphonServer else { return }

        if self.inputServerName.valueDidChange,
           let name = self.inputServerName.value
        {
            syphonServer.name = name
        }
            
        if self.needsInitialFrame || self.inputTexture.valueDidChange,
           let inputImage = self.inputTexture.value
        {
            let region = NSRect(origin: .zero,
                                size: CGSize(width: inputImage.texture.width, height: inputImage.texture.height))

            syphonServer.publishFrameTexture(inputImage.texture,
                                             on: commandBuffer,
                                             imageRegion: region,
                                             flipped: Self.syphonRequiresVerticalFlip(for: inputImage.textureTransform))
            self.needsInitialFrame = false
        }
    }

    /// Whether Syphon has to turn the frame over on its way into the shared
    /// surface.
    ///
    /// Syphon's surfaces are bottom-up, so a canonical top-left image is the
    /// one that needs turning over, and an image whose stored texture is
    /// already flipped is already in Syphon's orientation and goes across as
    /// it stands — which is what a frame from `SyphonClientNode` is.
    ///
    /// Which way round this goes was settled by looking rather than by reading
    /// Syphon's headers, and against another application rather than a loop
    /// back through Fabric, where the publishing and receiving claims cancel
    /// out: a canonical frame published from Spark Stage reads the right way up
    /// in Syphon Recorder with this, and upside down with what Fabric did
    /// before it.
    ///
    /// A flag can only say those two things. An image carrying any other
    /// transform — a movie's rotation, a crop — is published as though it were
    /// canonical, because there is nowhere in `publishFrameTexture` to put the
    /// rest of the matrix. Such a frame needs resampling into canonical
    /// orientation before it gets here.
    static func syphonRequiresVerticalFlip(for storedTextureTransform: simd_float4x4) -> Bool
    {
        storedTextureTransform != .textureVerticalFlip
    }
}

#endif // FABRIC_SYPHON_ENABLED
