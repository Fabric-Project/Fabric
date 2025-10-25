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
    public override var ports: [Port] { [ self.outputResolution, self.outputFrameNumber] + super.ports}
    
    public override var isDirty:Bool { true }
        
    public required init(context: Context)
    {
        self.outputResolution =  NodePort<simd_float2>(name: "Resolution" , kind: .Outlet)
        self.outputFrameNumber =  NodePort<Int>(name: "Frame Number" , kind: .Outlet)

        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case outputResolutionPort
        case outputFrameNumberPort
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.outputResolution, forKey: .outputResolutionPort)
        try container.encode(self.outputFrameNumber, forKey: .outputFrameNumberPort)

        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.outputResolution =  try container.decode(NodePort<simd_float2>.self, forKey: .outputResolutionPort)
        self.outputFrameNumber = try container.decode(NodePort<Int>.self, forKey: .outputFrameNumberPort)

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
}
