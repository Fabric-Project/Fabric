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
    public override class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    public override class var nodeTimeMode: Node.TimeMode { .None }
    public override class var nodeDescription: String { "Converts Pixels to default camera Units"}

    // Ports
    public let inputCursorPosition:NodePort<Float>
    public let outputUnitPosition:NodePort<Float>
    public override var ports: [Port] { [ self.inputCursorPosition, self.outputUnitPosition] + super.ports}
    
    public required init(context: Context)
    {
        self.inputCursorPosition = NodePort<Float>(name: "Pixel" , kind: .Inlet, description: "Position in pixels")
        self.outputUnitPosition = NodePort<Float>(name: "Unit" , kind: .Outlet, description: "Position in normalized units (-1 to 1)")

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

        self.inputCursorPosition = try container.decode(NodePort<Float>.self, forKey: .inputCursorPositionPort)
        self.outputUnitPosition = try container.decode(NodePort<Float>.self, forKey: .outputUnitPositionPort)

        try super.init(from: decoder)
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        
        if self.inputCursorPosition.valueDidChange,
           let pixel = self.inputCursorPosition.value,
           let graphRenderer = context.graphRenderer
        {
//            let aspect = graphRenderer.renderer.size.height/graphRenderer.renderer.size.width
            let size = simd_float2(x: graphRenderer.renderer.size.width,
                                   y: graphRenderer.renderer.size.height)
            
            let x = remap(pixel, 0.0, size.x, -1.0, 1.0)
            
            self.outputUnitPosition.send( x )
        }
    }
}
