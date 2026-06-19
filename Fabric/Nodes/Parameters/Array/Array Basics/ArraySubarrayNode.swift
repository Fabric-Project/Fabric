//
//  ArraySubarrayNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class ArraySubarrayNode<Value : PortValueRepresentable & Equatable> : Node
{
    public override class var name: String { "\(Value.portType.rawValue) Array Subarray" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Extracts a subset of a \(Value.portType.rawValue) array by offset and count. No new elements are synthesized; if offset is beyond the array bounds the output is empty." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputPort",   NodePort<ContiguousArray<Value>>(name: "Array",  kind: .Inlet,  description: "Input \(Value.portType.rawValue) array to subsample")),
            ("inputOffset", ParameterPort(parameter: IntParameter("Offset", 0, .inputfield, "Starting index in the input array"))),
            ("inputCount",  ParameterPort(parameter: IntParameter("Count",  0, .inputfield, "Maximum number of elements to extract"))),
            ("outputPort",  NodePort<ContiguousArray<Value>>(name: "Array",  kind: .Outlet, description: "Subarray extracted from the input")),
        ]
    }

    public var inputPort:   NodePort<ContiguousArray<Value>> { port(named: "inputPort") }
    public var inputOffset: ParameterPort<Int>               { port(named: "inputOffset") }
    public var inputCount:  ParameterPort<Int>               { port(named: "inputCount") }
    public var outputPort:  NodePort<ContiguousArray<Value>> { port(named: "outputPort") }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputPort.valueDidChange || self.inputOffset.valueDidChange || self.inputCount.valueDidChange else { return }

        guard let array = self.inputPort.value,
              let offset = self.inputOffset.value,
              let count = self.inputCount.value
        else
        {
            self.outputPort.send(ContiguousArray<Value>())
            return
        }

        if offset >= array.count
        {
            self.outputPort.send(ContiguousArray<Value>())
            return
        }

        self.outputPort.send(ContiguousArray(array.dropFirst(offset).prefix(count)))
    }
}
