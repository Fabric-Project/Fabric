//
//  Vector4ArrayToFloatArraysNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class Vector4ArrayToFloatArraysNode : Node
{
    public override class var name: String { "Vector 4 Array to Float Arrays" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Splits a Vector 4 Array into four parallel Float arrays — one per component (X, Y, Z, W). Each output has the same length as the input." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputArray", NodePort<ContiguousArray<simd_float4>>(name: "Vector 4 Array", kind: .Inlet, description: "Source array of (X, Y, Z, W) vectors")),
            ("outputX", NodePort<ContiguousArray<Float>>(name: "X", kind: .Outlet, description: "X component of each input vector")),
            ("outputY", NodePort<ContiguousArray<Float>>(name: "Y", kind: .Outlet, description: "Y component of each input vector")),
            ("outputZ", NodePort<ContiguousArray<Float>>(name: "Z", kind: .Outlet, description: "Z component of each input vector")),
            ("outputW", NodePort<ContiguousArray<Float>>(name: "W", kind: .Outlet, description: "W component of each input vector")),
        ]
    }

    public var inputArray: NodePort<ContiguousArray<simd_float4>> { port(named: "inputArray") }
    public var outputX: NodePort<ContiguousArray<Float>> { port(named: "outputX") }
    public var outputY: NodePort<ContiguousArray<Float>> { port(named: "outputY") }
    public var outputZ: NodePort<ContiguousArray<Float>> { port(named: "outputZ") }
    public var outputW: NodePort<ContiguousArray<Float>> { port(named: "outputW") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputArray.valueDidChange else { return }

        let source = self.inputArray.value ?? ContiguousArray<simd_float4>()
        let count = source.count
        var xs = ContiguousArray<Float>()
        var ys = ContiguousArray<Float>()
        var zs = ContiguousArray<Float>()
        var ws = ContiguousArray<Float>()
        xs.reserveCapacity(count)
        ys.reserveCapacity(count)
        zs.reserveCapacity(count)
        ws.reserveCapacity(count)
        for v in source {
            xs.append(v.x)
            ys.append(v.y)
            zs.append(v.z)
            ws.append(v.w)
        }
        self.outputX.send(xs)
        self.outputY.send(ys)
        self.outputZ.send(zs)
        self.outputW.send(ws)
    }
}
