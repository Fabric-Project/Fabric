//
//  MakeVector3ArrayNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class MakeVector3ArrayNode : Node
{
    public override class var name: String { "Make Vector 3 Array" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Zips three Float arrays componentwise into a Vector 3 array. Output length matches the longest input; shorter inputs pad with their last element (so a single-element array acts as a constant for that component). Unconnected or empty inputs default to 0." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputX", NodePort<ContiguousArray<Float>>(name: "X", kind: .Inlet, description: "X component, one per element")),
            ("inputY", NodePort<ContiguousArray<Float>>(name: "Y", kind: .Inlet, description: "Y component, one per element")),
            ("inputZ", NodePort<ContiguousArray<Float>>(name: "Z", kind: .Inlet, description: "Z component, one per element")),
            ("outputArray", NodePort<ContiguousArray<simd_float3>>(name: "Vector 3 Array", kind: .Outlet, description: "Array of (X, Y, Z) vectors")),
        ]
    }

    public var inputX: NodePort<ContiguousArray<Float>> { port(named: "inputX") }
    public var inputY: NodePort<ContiguousArray<Float>> { port(named: "inputY") }
    public var inputZ: NodePort<ContiguousArray<Float>> { port(named: "inputZ") }
    public var outputArray: NodePort<ContiguousArray<simd_float3>> { port(named: "outputArray") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputX.valueDidChange
            || self.inputY.valueDidChange
            || self.inputZ.valueDidChange
        else { return }

        let xIn = self.inputX.value
        let yIn = self.inputY.value
        let zIn = self.inputZ.value

        let count = [xIn?.count ?? 0, yIn?.count ?? 0, zIn?.count ?? 0].max() ?? 0
        guard count > 0 else {
            self.outputArray.send(ContiguousArray<simd_float3>())
            return
        }

        let xs = padLast(xIn, count: count)
        let ys = padLast(yIn, count: count)
        let zs = padLast(zIn, count: count)

        var output = ContiguousArray<simd_float3>()
        output.reserveCapacity(count)
        for i in 0..<count {
            output.append(simd_float3(xs[i], ys[i], zs[i]))
        }
        self.outputArray.send(output)
    }

    @inline(__always)
    private func padLast(_ array: ContiguousArray<Float>?, count: Int) -> [Float] {
        guard let array, !array.isEmpty else {
            return Array(repeating: 0, count: count)
        }
        if array.count >= count { return Array(array.prefix(count)) }
        return Array(array) + Array(repeating: array.last!, count: count - array.count)
    }
}
