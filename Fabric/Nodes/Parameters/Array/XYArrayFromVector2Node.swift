//
//  XYArrayFromVector2Node.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class XYArrayFromVector2Node : Node
{
    public override class var name: String { "XY Array From Vector 2" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Splits a Vector 2 array into its X and Y component Float arrays (the inverse of Vector 2 Array From XY)." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputArray", NodePort<ContiguousArray<simd_float2>>(name: "Vector 2 Array", kind: .Inlet, description: "Array of (X, Y) vectors")),
            ("outputX", NodePort<ContiguousArray<Float>>(name: "X", kind: .Outlet, description: "X component, one per element")),
            ("outputY", NodePort<ContiguousArray<Float>>(name: "Y", kind: .Outlet, description: "Y component, one per element")),
        ]
    }

    public var inputArray: NodePort<ContiguousArray<simd_float2>> { port(named: "inputArray") }
    public var outputX: NodePort<ContiguousArray<Float>> { port(named: "outputX") }
    public var outputY: NodePort<ContiguousArray<Float>> { port(named: "outputY") }

    public override func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputArray.valueDidChange else { return }
        guard let vectors = self.inputArray.value else {
            self.outputX.send(ContiguousArray<Float>())
            self.outputY.send(ContiguousArray<Float>())
            return
        }

        var xs = ContiguousArray<Float>(); xs.reserveCapacity(vectors.count)
        var ys = ContiguousArray<Float>(); ys.reserveCapacity(vectors.count)
        for v in vectors {
            xs.append(v.x)
            ys.append(v.y)
        }
        self.outputX.send(xs)
        self.outputY.send(ys)
    }
}
