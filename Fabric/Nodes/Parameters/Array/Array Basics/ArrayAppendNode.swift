//
//  ArrayAppendNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class ArrayAppendNode<Value : PortValueRepresentable & Equatable> : Node
{
    public override class var name: String { "\(Value.portType.rawValue) Array Append" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Appends Array B onto the end of Array A, producing a single concatenated \(Value.portType.rawValue) array." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputArrayA", NodePort<ContiguousArray<Value>>(name: "Array A", kind: .Inlet, description: "First \(Value.portType.rawValue) array")),
            ("inputArrayB", NodePort<ContiguousArray<Value>>(name: "Array B", kind: .Inlet, description: "Second \(Value.portType.rawValue) array, appended after Array A")),
            ("outputPort",  NodePort<ContiguousArray<Value>>(name: "Array",   kind: .Outlet, description: "Concatenated \(Value.portType.rawValue) array")),
        ]
    }

    public var inputArrayA: NodePort<ContiguousArray<Value>> { port(named: "inputArrayA") }
    public var inputArrayB: NodePort<ContiguousArray<Value>> { port(named: "inputArrayB") }
    public var outputPort:  NodePort<ContiguousArray<Value>> { port(named: "outputPort") }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputArrayA.valueDidChange || self.inputArrayB.valueDidChange else { return }

        let a = self.inputArrayA.value ?? []
        let b = self.inputArrayB.value ?? []
        self.outputPort.send(a + b)
    }
}
