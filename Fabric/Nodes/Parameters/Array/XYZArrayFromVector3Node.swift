//
//  XYZArrayFromVector3Node.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class XYZArrayFromVector3Node : Node
{
    public override class var name: String { "XYZ Array From Vector 3" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Splits a Vector 3 array into its X, Y and Z component Float arrays (the inverse of Vector 3 Array From XYZ)." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputArray", NodePort<ContiguousArray<simd_float3>>(name: "Vector 3 Array", kind: .Inlet, description: "Array of (X, Y, Z) vectors")),
            ("outputX", NodePort<ContiguousArray<Float>>(name: "X", kind: .Outlet, description: "X component, one per element")),
            ("outputY", NodePort<ContiguousArray<Float>>(name: "Y", kind: .Outlet, description: "Y component, one per element")),
            ("outputZ", NodePort<ContiguousArray<Float>>(name: "Z", kind: .Outlet, description: "Z component, one per element")),
        ]
    }

    public var inputArray: NodePort<ContiguousArray<simd_float3>> { port(named: "inputArray") }
    public var outputX: NodePort<ContiguousArray<Float>> { port(named: "outputX") }
    public var outputY: NodePort<ContiguousArray<Float>> { port(named: "outputY") }
    public var outputZ: NodePort<ContiguousArray<Float>> { port(named: "outputZ") }

    public override func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputArray.valueDidChange else { return }
        guard let vectors = self.inputArray.value else {
            self.outputX.send(ContiguousArray<Float>())
            self.outputY.send(ContiguousArray<Float>())
            self.outputZ.send(ContiguousArray<Float>())
            return
        }

        var xs = ContiguousArray<Float>(); xs.reserveCapacity(vectors.count)
        var ys = ContiguousArray<Float>(); ys.reserveCapacity(vectors.count)
        var zs = ContiguousArray<Float>(); zs.reserveCapacity(vectors.count)
        for v in vectors {
            xs.append(v.x)
            ys.append(v.y)
            zs.append(v.z)
        }
        self.outputX.send(xs)
        self.outputY.send(ys)
        self.outputZ.send(zs)
    }
}
