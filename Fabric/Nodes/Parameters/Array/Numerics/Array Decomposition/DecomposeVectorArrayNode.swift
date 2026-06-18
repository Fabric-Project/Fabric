//
//  DecomposeVectorArrayNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class DecomposeVectorArrayNode<Value: PortValueRepresentable & ComponentRepresentable>: Node
{
    public override class var name: String { "\(Value.portType.rawValue) Array Decompose" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Splits a \(Value.portType.rawValue) array into its \(Value.componentLabels.joined(separator: ", ")) component arrays." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        let outputPorts: [(name: String, port: Port)] = Value.componentLabels.enumerated().map { (i, label) in
            ("outputComponent\(i)", NodePort<ContiguousArray<Value.Component>>(name: label, kind: .Outlet, description: "\(label) component, one per element"))
        }

        return ports +
        [
            ("inputArray", NodePort<ContiguousArray<Value>>(name: "\(Value.portType.rawValue) Array", kind: .Inlet, description: "Array of \(Value.portType.rawValue) values")),
        ] + outputPorts
    }

    public var inputArray: NodePort<ContiguousArray<Value>> { port(named: "inputArray") }
    private func outputComponentPort(_ i: Int) -> NodePort<ContiguousArray<Value.Component>> { port(named: "outputComponent\(i)") }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputArray.valueDidChange else { return }
        let componentCount = Value.componentLabels.count

        guard let values = self.inputArray.value else {
            for i in 0..<componentCount { outputComponentPort(i).send(ContiguousArray<Value.Component>()) }
            return
        }

        var componentArrays = [ContiguousArray<Value.Component>](repeating: ContiguousArray<Value.Component>(), count: componentCount)
        for i in 0..<componentCount { componentArrays[i].reserveCapacity(values.count) }

        for value in values {
            let components = value.componentValues
            for i in 0..<componentCount {
                componentArrays[i].append(components[i])
            }
        }

        for i in 0..<componentCount {
            outputComponentPort(i).send(componentArrays[i])
        }
    }
}
