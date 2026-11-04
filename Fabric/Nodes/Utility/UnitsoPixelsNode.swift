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
    public let inputUnitPosition = ParameterPort(parameter: FloatParameter("Unit", 0, -1, 1, .inputfield, "Position in normalized units (-1 to 1)"))
    public let outputPixelPosition = NodePort<Float>(name: "Pixel", kind: .Outlet, description: "Position in pixels")

    public override func declaredPorts() -> [PortDeclaration]
    {
        [
            PortDeclaration(key: "inputUnitPositionPort", port: self.inputUnitPosition),
            PortDeclaration(key: "outputCursorPositionPort", port: self.outputPixelPosition),
        ] + super.declaredPorts()
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
