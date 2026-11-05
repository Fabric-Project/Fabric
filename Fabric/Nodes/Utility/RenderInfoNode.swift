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
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("outputWidth", NodePort<Float>(name: "Width", kind: .Outlet, description: "Render target width in pixels")),
            ("outputHeight", NodePort<Float>(name: "Height", kind: .Outlet, description: "Render target height in pixels")),
            ("outputFrameNumber", NodePort<Int>(name: "Frame Number", kind: .Outlet, description: "Current execution frame count")),
        ]
    }
    public var outputWidth: NodePort<Float> { _outputWidth }
    private var _outputWidth: NodePort<Float>!
    public var outputHeight: NodePort<Float> { _outputHeight }
    private var _outputHeight: NodePort<Float>!
    public var outputFrameNumber: NodePort<Int> { _outputFrameNumber }
    private var _outputFrameNumber: NodePort<Int>!

    
    public var inputTexturePort: NodePort<FabricImage> { _inputTexturePort }
    private var _inputTexturePort: NodePort<FabricImage>!
    public var outputTexturePort: NodePort<FabricImage> { _outputTexturePort }
    private var _outputTexturePort: NodePort<FabricImage>!

    override public func bindPorts()
    {
        super.bindPorts()
        self._outputWidth = findPort(named: "outputWidth")
        self._outputHeight = findPort(named: "outputHeight")
        self._outputFrameNumber = findPort(named: "outputFrameNumber")
        self._inputTexturePort = findPort(named: "inputTexturePort")
        self._outputTexturePort = findPort(named: "outputTexturePort")
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
