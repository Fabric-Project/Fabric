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
            ("outputWidth", NodePort<Float>(name: "Width", kind: .Outlet)),
            ("outputHeight", NodePort<Float>(name: "Height", kind: .Outlet)),
            ("outputFrameNumber", NodePort<Int>(name: "Frame Number", kind: .Outlet)),
        ]
    }
    public var outputWidth:NodePort<Float>  { port(named: "outputWidth") }
    public var outputHeight:NodePort<Float> { port(named: "outputHeight") }
    public var outputFrameNumber:NodePort<Int> { port(named: "outputFrameNumber") }

    
    public var inputTexturePort:NodePort<EquatableTexture>  { port(named: "inputTexturePort") }
    public var outputTexturePort:NodePort<EquatableTexture> { port(named: "outputTexturePort") }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if let graphRenderer = context.graphRenderer
        {
            let size = graphRenderer.renderer.size
            self.outputWidth.send( size.width )
            self.outputHeight.send( size.height )
            self.outputFrameNumber.send( graphRenderer.executionCount )
        }
    }
}
