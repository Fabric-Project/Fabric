//
//  ArrayLastValueNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class ArrayLastValueNode: TypeAgnosticNode
{
    public override class var name: String { "Array Last Value" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Returns the last element of an array. Choose element type in Settings." }
    override public class var includesArrayTypesInStrategy: Bool { false }

    public override func declaredPorts() -> [PortDeclaration]
    {
        guard let elementType = strategy as? PortType else { return super.declaredPorts() }

        let arrayType: PortType = .Array(portType: elementType)

        return [
            PortDeclaration(key: "inputPort", portType: arrayType, kind: .Inlet, name: "Array", description: "Input array to get the last value from"),
            PortDeclaration(key: "outputPort", portType: elementType, kind: .Outlet, name: "Value", description: "Last element of the array"),
        ] + super.declaredPorts()
    }

    private var boundInputPort: Port?
    private var boundOutputPort: Port?

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundInputPort = findPort(named: "inputPort")
        self.boundOutputPort = findPort(named: "outputPort")
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputPort:  Port = self.boundInputPort,
              let outputPort: Port = self.boundOutputPort else { return }

        guard inputPort.valueDidChange else { return }

        guard let boxed = inputPort.snapshotValue(),
              case .Array(let elements) = boxed,
              let last = elements.last else { return }

        outputPort.sendBoxed(last)
    }
}
