//
//  ArraySplitAtIndexNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class ArraySplitAtIndexNode<Value : PortValueRepresentable & Equatable> : Node
{
    public override class var name: String { "\(Value.portType.rawValue) Array Split at Index" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Splits a \(Value.portType.rawValue) array at Index into two arrays: elements before the index and elements from the index onward." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputPort",    NodePort<ContiguousArray<Value>>(name: "Array",  kind: .Inlet,  description: "Input \(Value.portType.rawValue) array to split")),
            ("inputIndex",   ParameterPort(parameter: IntParameter("Index", 0, .inputfield, "Split position; elements before this index go to Before, elements from this index onward go to From"))),
            ("outputBefore", NodePort<ContiguousArray<Value>>(name: "Before", kind: .Outlet, description: "Elements at indices 0 ..< Index")),
            ("outputFrom",   NodePort<ContiguousArray<Value>>(name: "From",   kind: .Outlet, description: "Elements at indices Index ..< count")),
        ]
    }

    public var inputPort:    NodePort<ContiguousArray<Value>> { port(named: "inputPort") }
    public var inputIndex:   ParameterPort<Int>               { port(named: "inputIndex") }
    public var outputBefore: NodePort<ContiguousArray<Value>> { port(named: "outputBefore") }
    public var outputFrom:   NodePort<ContiguousArray<Value>> { port(named: "outputFrom") }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputPort.valueDidChange || self.inputIndex.valueDidChange else { return }

        guard let array = self.inputPort.value,
              let index = self.inputIndex.value
        else
        {
            self.outputBefore.send(ContiguousArray<Value>())
            self.outputFrom.send(ContiguousArray<Value>())
            return
        }

        let clamped = max(0, min(index, array.count))
        self.outputBefore.send(ContiguousArray(array[0..<clamped]))
        self.outputFrom.send(ContiguousArray(array[clamped...]))
    }
}
