//
//  ArrayShuffleNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class ArrayShuffleNode<Value : PortValueRepresentable & Equatable> : Node
{
    public override class var name: String { "\(Value.portType.rawValue) Array Shuffle" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Randomizes the element order of a \(Value.portType.rawValue) array when Shuffle is true; passes the array through unchanged when false." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputPort",    NodePort<ContiguousArray<Value>>(name: "Array",   kind: .Inlet,  description: "Input \(Value.portType.rawValue) array")),
            ("inputShuffle", NodePort<Bool>(name: "Shuffle", kind: .Inlet, description: "When true, randomizes element order; when false, passes through unchanged")),
            ("outputPort",   NodePort<ContiguousArray<Value>>(name: "Array",   kind: .Outlet, description: "Shuffled or original \(Value.portType.rawValue) array")),
        ]
    }

    public var inputPort:    NodePort<ContiguousArray<Value>> { port(named: "inputPort") }
    public var inputShuffle: NodePort<Bool>                   { port(named: "inputShuffle") }
    public var outputPort:   NodePort<ContiguousArray<Value>> { port(named: "outputPort") }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputPort.valueDidChange || self.inputShuffle.valueDidChange else { return }

        guard let array = self.inputPort.value else { return }

        if self.inputShuffle.value == true
        {
            var shuffled = array
            shuffled.shuffle()
            self.outputPort.send(shuffled)
        }
        else
        {
            self.outputPort.send(array)
        }
    }
}
