//
//  MakeColorNode.swift
//  Fabric
//
//  Created by Claude on 4/11/26.
//

import Foundation
import Satin
import simd
import Metal

/// Constructs a color from individual R, G, B, A float components.
public class MakeColorNode: Node
{
    override public class var name: String { "Color From RGBA" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Color) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Converts 4 numerical components to a Color" }

    // Ports
    public let inputR = ParameterPort(parameter: FloatParameter("R", 0.0, .inputfield, "Red component (0–1)"))
    public let inputG = ParameterPort(parameter: FloatParameter("G", 0.0, .inputfield, "Green component (0–1)"))
    public let inputB = ParameterPort(parameter: FloatParameter("B", 0.0, .inputfield, "Blue component (0–1)"))
    public let inputA = ParameterPort(parameter: FloatParameter("A", 1.0, .inputfield, "Alpha component (0–1)"))
    public let outputColor: NodePort<simd_float4> = ColorNodePort(name: "Color", kind: .Outlet, description: "Combined RGBA color")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputR", port: self.inputR),
            PortDeclaration(key: "inputG", port: self.inputG),
            PortDeclaration(key: "inputB", port: self.inputB),
            PortDeclaration(key: "inputA", port: self.inputA),
            PortDeclaration(key: "outputColor", port: self.outputColor),
        ]
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if self.inputR.valueDidChange || self.inputG.valueDidChange || self.inputB.valueDidChange || self.inputA.valueDidChange,
           let r = self.inputR.value,
           let g = self.inputG.value,
           let b = self.inputB.value,
           let a = self.inputA.value
        {
            self.outputColor.send(simd_float4(r, g, b, a))
        }
    }
}
