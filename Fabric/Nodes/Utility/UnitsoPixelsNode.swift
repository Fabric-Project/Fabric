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
    public override class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    public override class var nodeTimeMode: Node.TimeMode { .None }
    public override class var nodeDescription: String { "Converts Units in default camera space to Pixels"}

    // Ports
    public let inputUnitPosition:ParameterPort<Float>
    public let outputPixelPosition:NodePort<Float>
    public override var ports: [Port] { [ self.inputUnitPosition, self.outputPixelPosition ] + super.ports}

    public required init(context: Context)
    {
        self.inputUnitPosition = ParameterPort(parameter: FloatParameter("Unit", 0, -1, 1, .inputfield, "Position in normalized units (-1 to 1)"))
        self.outputPixelPosition = NodePort<Float>(name: "Pixel" , kind: .Outlet, description: "Position in pixels")

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

        if let decoded = try? container.decode(ParameterPort<Float>.self, forKey: .inputUnitPositionPort)
        {
            self.inputUnitPosition = decoded
        }
        else
        {
            // Pre-existing documents saved this port as a plain NodePort<Float>
            // with no backing parameter (see issue #343). Adopt the legacy
            // port's identity so saved connections survive; the value itself
            // was never persisted by the legacy port, so the fresh parameter's
            // default stands.
            let legacy = try container.decode(NodePort<Float>.self, forKey: .inputUnitPositionPort)
            let fresh = ParameterPort(parameter: FloatParameter("Unit", 0, -1, 1, .inputfield, "Position in normalized units (-1 to 1)"))
            fresh.hydrate(from: legacy)
            self.inputUnitPosition = fresh
        }
        self.outputPixelPosition = try container.decode(NodePort<Float>.self, forKey: .outputCursorPositionPort)

        try super.init(from: decoder)
    }
    
    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        
        if self.inputUnitPosition.valueDidChange,
           let unit = self.inputUnitPosition.value
        {
//            let aspect = graphRenderer.renderer.size.height/graphRenderer.renderer.size.width
            let size = simd_float2(x: renderer.renderEncoder.size.width,
                                   y: renderer.renderEncoder.size.height)
            
            let x = remap( unit, -1.0, 1.0, 0.0, size.x)

            self.outputPixelPosition.send( x )
            
        }
        
    }
}
