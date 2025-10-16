//
//  PixelsToUnitsNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/16/25.
//

import Foundation
import Satin
import Metal
import simd

public class PixelsToUnitsNode : Node
{
    public override class var name:String { "Pixels to Units" }
    public override class var nodeType:Node.NodeType { Node.NodeType.Utility }
    
    // Ports
    public let inputCursorPosition:NodePort<simd_float2>
    public let outputUnitPosition:NodePort<simd_float3>
    public override var ports: [AnyPort] { [ self.inputCursorPosition, self.outputUnitPosition] + super.ports}
    
    public required init(context: Context)
    {
        self.inputCursorPosition = NodePort<simd_float2>(name: "Position" , kind: .Inlet)
        self.outputUnitPosition = NodePort<simd_float3>(name: "Units" , kind: .Outlet)

        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputCursorPositionPort
        case outputUnitPositionPort
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputCursorPosition, forKey: .inputCursorPositionPort)
        try container.encode(self.outputUnitPosition, forKey: .outputUnitPositionPort)

        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputCursorPosition = try container.decode(NodePort<simd_float2>.self, forKey: .inputCursorPositionPort)
        self.outputUnitPosition = try container.decode(NodePort<simd_float3>.self, forKey: .outputUnitPositionPort)

        try super.init(from: decoder)
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        
        if self.inputCursorPosition.valueDidChange,
           let position = self.inputCursorPosition.value,
           let graphRenderer = context.graphRenderer
        {
            let aspect = graphRenderer.renderer.size.height/graphRenderer.renderer.size.width
            let size = simd_float2(x: graphRenderer.renderer.size.width,
                                   y: graphRenderer.renderer.size.height)
            
            let x = remap(position.x, 0.0, size.x, -1.0, 1.0)
            
            let y = remap(position.y, 0.0, size.y, -aspect, aspect)

            
            self.outputUnitPosition.send( simd_float3(x: x, y: y, z:0.0) )
            
        }
        
    }
}
