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
    public let inputCursorPosition = ParameterPort(parameter: FloatParameter("Pixel", 0, -8192, 8192, .inputfield, "Position in pixels"))
    public let outputUnitPosition = NodePort<Float>(name: "Unit", kind: .Outlet, description: "Position in normalized units (-1 to 1)")

    public override func declaredPorts() -> [PortDeclaration]
    {
        [
            PortDeclaration(key: "inputPixelPositionPort", port: self.inputCursorPosition),
            PortDeclaration(key: "outputUnitPositionPort", port: self.outputUnitPosition),
        ] + super.declaredPorts()
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        
        if self.inputCursorPosition.valueDidChange,
           let pixel = self.inputCursorPosition.value
        {
//            let aspect = graphRenderer.renderer.size.height/graphRenderer.renderer.size.width
            let size = simd_float2(x: renderer.renderEncoder.size.width,
                                   y: renderer.renderEncoder.size.height)
            
            let x = remap(pixel, 0.0, size.x, -1.0, 1.0)
            
            self.outputUnitPosition.send( x )
        }
    }
}
