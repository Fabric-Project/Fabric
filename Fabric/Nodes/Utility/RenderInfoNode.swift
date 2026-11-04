//
//  RenderInfoNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/15/25.
//

import Foundation
import Satin
import Metal
import simd

public class RenderInfoNode : Node
{
    public override class var name:String { "Rendering Info" }
    public override class var nodeType:Node.NodeType { Node.NodeType.Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Rendering Destination Info" }

    // Ports
    public let outputWidth = NodePort<Float>(name: "Width", kind: .Outlet, description: "Render target width in pixels")
    public let outputHeight = NodePort<Float>(name: "Height", kind: .Outlet, description: "Render target height in pixels")
    public let outputFrameNumber = NodePort<Int>(name: "Frame Number", kind: .Outlet, description: "Current execution frame count")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "outputWidth", port: self.outputWidth),
            PortDeclaration(key: "outputHeight", port: self.outputHeight),
            PortDeclaration(key: "outputFrameNumber", port: self.outputFrameNumber),
        ]
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        let size = renderer.renderEncoder.size
        self.outputWidth.send( size.width )
        self.outputHeight.send( size.height )
        self.outputFrameNumber.send( executionInfo.timing.frameNumber )
    }
}
