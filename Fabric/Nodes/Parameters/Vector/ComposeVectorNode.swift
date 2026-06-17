//
//  ComposeVectorNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class ComposeVectorNode<Value: PortValueRepresentable & ComponentRepresentable>: Node
{
    public override class var name: String { "\(Value.portType.rawValue) Compose" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Vector) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Combines \(Value.componentLabels.joined(separator: ", ")) components into a \(Value.portType.rawValue)" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        let componentPorts: [(name: String, port: Port)] = Value.componentLabels.enumerated().map { (i, label) in
            ("inputComponent\(i)", makeInspectorValuePort(Value.Component.self, name: label, description: "\(label) component"))
        }

        return ports + componentPorts +
        [
            ("outputVector", NodePort<Value>(name: Value.portType.rawValue, kind: .Outlet, description: "Combined \(Value.portType.rawValue)")),
        ]
    }

    private func inputComponentPort(_ i: Int) -> NodePort<Value.Component> { port(named: "inputComponent\(i)") }
    public var outputVector: NodePort<Value> { port(named: "outputVector") }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let componentPorts = (0..<Value.componentLabels.count).map { inputComponentPort($0) }
        guard componentPorts.contains(where: { $0.valueDidChange }) else { return }

        let values = componentPorts.map { $0.value ?? Value.Component.defaultValue! }
        self.outputVector.send(Value(componentValues: values))
    }
}
