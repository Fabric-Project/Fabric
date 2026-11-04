//
//  RepeatValueNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class RepeatValueNode<Value : PortValueRepresentable & ParameterValueType> : Node
{
    public override class var name: String { "\(Value.portType.rawValue) Repeat Value" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Replicates a single \(Value.portType.rawValue) value into an array of the given count." }

    public let inputValue = NodePort<Value>.makeFresh(name: "Value", kind: .Inlet, description: "Value to place in every array element")
    public let inputCount = ParameterPort(parameter: IntParameter("Count", 6, 0, 1024, .inputfield, "Number of elements to fill"))
    public let outputArray = NodePort<ContiguousArray<Value>>(name: "Array", kind: .Outlet, description: "Array of length Count containing Value in every slot")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputValue", port: self.inputValue),
            PortDeclaration(key: "inputCount", port: self.inputCount),
            PortDeclaration(key: "outputArray", port: self.outputArray),
        ]
    }

    // ParameterPort<T> is a subclass of NodePort<T>, so this accessor type is
    // compatible whether the concrete port is a ParameterPort or a NodePort.

    public override func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard self.inputValue.valueDidChange || self.inputCount.valueDidChange else { return }
        guard let value = self.inputValue.value, let rawCount = self.inputCount.value else { return }

        let count = max(0, rawCount)
        let output = ContiguousArray<Value>(repeating: value, count: count)
        self.outputArray.send(output)
    }
}
