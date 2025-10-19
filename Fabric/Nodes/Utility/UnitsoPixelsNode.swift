//
//  UnitsoPixelsNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/16/25.
//

import Foundation
import Satin
import Metal
import simd

public class UnitsoPixelsNode : Node
{
    public override class var name:String { "Units to Pixels" }
    public override class var nodeType:Node.NodeType { Node.NodeType.Utility }
    
    // Ports
    public let inputUnitPosition:NodePort<simd_float3>
    public let outputPixelPosition:NodePort<simd_float2>
    public override var ports: [Port] { [ self.inputUnitPosition, self.outputPixelPosition ] + super.ports}
    
    public required init(context: Context)
    {
        self.inputUnitPosition = NodePort<simd_float3>(name: "Units" , kind: .Inlet)
        self.outputPixelPosition = NodePort<simd_float2>(name: "Position" , kind: .Outlet)

        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputUnitPositionPort
        case outputCursorPositionPort
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputUnitPosition, forKey: .inputUnitPositionPort)
        try container.encode(self.outputPixelPosition, forKey: .outputCursorPositionPort)

        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputUnitPosition = try container.decode(NodePort<simd_float3>.self, forKey: .inputUnitPositionPort)
        self.outputPixelPosition = try container.decode(NodePort<simd_float2>.self, forKey: .outputCursorPositionPort)

        try super.init(from: decoder)
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        
        if self.inputUnitPosition.valueDidChange,
           let position = self.inputUnitPosition.value,
           let graphRenderer = context.graphRenderer
        {
            let aspect = graphRenderer.renderer.size.height/graphRenderer.renderer.size.width
            let size = simd_float2(x: graphRenderer.renderer.size.width,
                                   y: graphRenderer.renderer.size.height)
            
            let x = remap( position.x, -1.0, 1.0, 0.0, size.x)

            let y = remap(position.y, -aspect, aspect, 0.0, size.y)
            
            self.outputPixelPosition.send( simd_float2(x: x, y: y) )
            
        }
        
    }
}
