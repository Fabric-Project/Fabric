//
//  ComposeVectorArrayNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class ComposeVectorArrayNode<Value: PortValueRepresentable & ComponentRepresentable>: Node
{
    public override class var name: String { "\(Value.portType.rawValue) Array Compose" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Zips the \(Value.componentLabels.joined(separator: ", ")) component arrays componentwise into a \(Value.portType.rawValue) array. Output length matches the longest input; shorter inputs pad with their last element (so a single-element array acts as a constant for that component). Unconnected or empty inputs default to 0." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        let componentPorts: [(name: String, port: Port)] = Value.componentLabels.enumerated().map { (i, label) in
            ("inputComponent\(i)", NodePort<ContiguousArray<Value.Component>>(name: label, kind: .Inlet, description: "\(label) component, one per element"))
        }

        return ports + componentPorts +
        [
            ("outputArray", NodePort<ContiguousArray<Value>>(name: "\(Value.portType.rawValue) Array", kind: .Outlet, description: "Array of combined \(Value.portType.rawValue) values")),
        ]
    }

    private func inputComponentPort(_ i: Int) -> NodePort<ContiguousArray<Value.Component>> { port(named: "inputComponent\(i)") }
    public var outputArray: NodePort<ContiguousArray<Value>> { port(named: "outputArray") }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let componentPorts = (0..<Value.componentLabels.count).map { inputComponentPort($0) }
        guard componentPorts.contains(where: { $0.valueDidChange }) else { return }

        let count = componentPorts.map { $0.value?.count ?? 0 }.max() ?? 0
        guard count > 0 else {
            self.outputArray.send(ContiguousArray<Value>())
            return
        }

        let fallback = Value.Component.defaultValue!
        let padded = componentPorts.map { ($0.value ?? []).paddedToLast(count: count, fallback: fallback) }

        var output = ContiguousArray<Value>()
        output.reserveCapacity(count)
        for i in 0..<count {
            output.append(Value(componentValues: padded.map { $0[i] }))
        }
        self.outputArray.send(output)
    }
}
