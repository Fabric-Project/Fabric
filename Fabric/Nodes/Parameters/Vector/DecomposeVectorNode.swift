//
//  DecomposeVectorNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class DecomposeVectorNode<Value: PortValueRepresentable & ComponentRepresentable & DefaultParameterProviding>: Node
{
    public override class var name: String { "\(Value.portType.rawValue) Decompose" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Vector) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Splits a \(Value.portType.rawValue) into its \(Value.componentLabels.joined(separator: ", ")) components" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        let outputPorts: [(name: String, port: Port)] = Value.componentLabels.enumerated().map { (i, label) in
            ("outputComponent\(i)", NodePort<Value.Component>(name: label, kind: .Outlet, description: "\(label) component"))
        }

        return ports +
        [
            ("inputVector", Value.makeDefaultParameterPort(name: Value.portType.rawValue, description: "Vector to decompose into components")),
        ] + outputPorts
    }

    public var inputVector: NodePort<Value> { port(named: "inputVector") }
    private func outputComponentPort(_ i: Int) -> NodePort<Value.Component> { port(named: "outputComponent\(i)") }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputVector.valueDidChange, let vector = self.inputVector.value else { return }

        for (i, value) in vector.componentValues.enumerated() {
            outputComponentPort(i).send(value)
        }
    }
}
