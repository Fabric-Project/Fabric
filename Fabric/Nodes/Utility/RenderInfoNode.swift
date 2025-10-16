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
    
    // Ports
    public let outputResolution:NodePort<simd_float2> = NodePort<simd_float2>(name: "Resolution" , kind: .Outlet)
    public let outputFrameNumber:NodePort<Int> = NodePort<Int>(name: "Frame Number" , kind: .Outlet)
    public override var ports: [AnyPort] { [ self.outputResolution, self.outputFrameNumber] + super.ports}
    
    public override var isDirty:Bool { true }
        
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if let graphRenderer = context.graphRenderer
        {
            let size = graphRenderer.renderer.size
            let resolution = simd_float2(x: size.width, y:size.height)
            self.outputResolution.send( resolution )
            self.outputFrameNumber.send( graphRenderer.executionCount )
        }
    }
}
