//
//  ArrayConcatNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class ArrayConcatNode<Value : PortValueRepresentable & Equatable> : Node
{
    public override class var name:String { "\(Value.portType.rawValue) Array Concat" }
    public override class var nodeType:Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Concatenate two \(Value.portType.rawValue) Arrays end-to-end (A then B)." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputArrayA", NodePort<ContiguousArray<Value>>(name: "Array A", kind: .Inlet, description: "First array; its elements appear before B's in the output")),
            ("inputArrayB", NodePort<ContiguousArray<Value>>(name: "Array B", kind: .Inlet, description: "Second array; its elements appear after A's in the output")),
            ("outputPort",  NodePort<ContiguousArray<Value>>(name: "Array", kind: .Outlet, description: "Concatenation of Array A followed by Array B")),
        ]
    }

    public var inputArrayA: NodePort<ContiguousArray<Value>> { port(named: "inputArrayA") }
    public var inputArrayB: NodePort<ContiguousArray<Value>> { port(named: "inputArrayB") }
    public var outputPort:  NodePort<ContiguousArray<Value>> { port(named: "outputPort") }

    override public func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputArrayA.valueDidChange || self.inputArrayB.valueDidChange else { return }

        let a = self.inputArrayA.value ?? ContiguousArray<Value>()
        let b = self.inputArrayB.value ?? ContiguousArray<Value>()
        // Either input absent (and the other present) is treated as the
        // empty array — equivalent to a no-op pass-through of the
        // present side. Both absent → empty output.
        var out = ContiguousArray<Value>()
        out.reserveCapacity(a.count + b.count)
        out.append(contentsOf: a)
        out.append(contentsOf: b)
        self.outputPort.send(out)
    }
}
