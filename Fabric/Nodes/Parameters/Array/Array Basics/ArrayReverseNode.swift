//
//  ArrayReverseNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class ArrayReverseNode<Value : PortValueRepresentable & Equatable> : Node
{
    public override class var name: String { "\(Value.portType.rawValue) Array Reverse" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Reverses the element order of a \(Value.portType.rawValue) array." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputPort",  NodePort<ContiguousArray<Value>>(name: "Array", kind: .Inlet,  description: "Input \(Value.portType.rawValue) array")),
            ("outputPort", NodePort<ContiguousArray<Value>>(name: "Array", kind: .Outlet, description: "Reversed \(Value.portType.rawValue) array")),
        ]
    }

    public var inputPort:  NodePort<ContiguousArray<Value>> { port(named: "inputPort") }
    public var outputPort: NodePort<ContiguousArray<Value>> { port(named: "outputPort") }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputPort.valueDidChange else { return }

        guard let array = self.inputPort.value else { return }

        self.outputPort.send(ContiguousArray(array.reversed()))
    }
}
