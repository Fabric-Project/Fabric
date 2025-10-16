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
    public let outputResolution:NodePort<simd_float2>
    public let outputFrameNumber:NodePort<Int>
    public override var ports: [AnyPort] { [ self.outputResolution, self.outputFrameNumber] + super.ports}
    
    public override var isDirty:Bool { true }
    
    public required init(context: Context)
    {
        self.outputResolution =  NodePort<simd_float2>(name: "Resolution" , kind: .Outlet)
        self.outputFrameNumber =  NodePort<Int>(name: "Frame Number" , kind: .Outlet)

        super.init(context: context)
    }
    
    public required init(from decoder: any Decoder) throws
    {
//        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.outputResolution =  NodePort<simd_float2>(name: "Resolution" , kind: .Outlet)
        self.outputFrameNumber =  NodePort<Int>(name: "Frame Number" , kind: .Outlet)

        try super.init(from: decoder)
    }
    
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
    
//    public override func resize(size: (width: Float, height: Float), scaleFactor: Float)
//    {
//        print("Render Info Resize")
//        
//        self.markDirty()
//    }
}
