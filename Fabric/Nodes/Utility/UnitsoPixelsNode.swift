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
    public let inputUnitPosition:NodePort<simd_float3> = NodePort<simd_float3>(name: "Units" , kind: .Outlet)
    public let outputPixelPosition:NodePort<simd_float2> = NodePort<simd_float2>(name: "Position" , kind: .Inlet)
    public override var ports: [AnyPort] { [ self.inputUnitPosition, self.outputPixelPosition ] + super.ports}
    
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
