//
//  Vector2ArrayToFloatArraysNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class Vector2ArrayToFloatArraysNode : Node
{
    public override class var name: String { "Vector 2 Array to Float Arrays" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Splits a Vector 2 Array into two parallel Float arrays — one per component (X, Y). Each output has the same length as the input." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputArray", NodePort<ContiguousArray<simd_float2>>(name: "Vector 2 Array", kind: .Inlet, description: "Source array of (X, Y) vectors")),
            ("outputX", NodePort<ContiguousArray<Float>>(name: "X", kind: .Outlet, description: "X component of each input vector")),
            ("outputY", NodePort<ContiguousArray<Float>>(name: "Y", kind: .Outlet, description: "Y component of each input vector")),
        ]
    }

    public var inputArray: NodePort<ContiguousArray<simd_float2>> { port(named: "inputArray") }
    public var outputX: NodePort<ContiguousArray<Float>> { port(named: "outputX") }
    public var outputY: NodePort<ContiguousArray<Float>> { port(named: "outputY") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputArray.valueDidChange else { return }

        let source = self.inputArray.value ?? ContiguousArray<simd_float2>()
        let count = source.count
        var xs = ContiguousArray<Float>()
        var ys = ContiguousArray<Float>()
        xs.reserveCapacity(count)
        ys.reserveCapacity(count)
        for v in source {
            xs.append(v.x)
            ys.append(v.y)
        }
        self.outputX.send(xs)
        self.outputY.send(ys)
    }
}
