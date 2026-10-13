//
//  ArrayFirstValueNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class ArrayFirstValueNode: TypeAgnosticNode
{
    public override class var name: String { "Array First Value" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Returns the first element of an array. Choose element type in Settings." }
    override public class var includesArrayTypesInStrategy: Bool { false }

    public override func declaredPorts() -> [PortDeclaration]
    {
        guard let elementType = PortType(rawValue: strategy) else { return super.declaredPorts() }

        let arrayType: PortType = .Array(portType: elementType)

        return [
            PortDeclaration(registryKey: "inputPort", portType: arrayType, kind: .Inlet, name: "Array", description: "Input array to get the first value from"),
            PortDeclaration(registryKey: "outputPort", portType: elementType, kind: .Outlet, name: "Value", description: "First element of the array"),
        ] + super.declaredPorts()
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputPort:  Port = findPort(named: "inputPort"),
              let outputPort: Port = findPort(named: "outputPort") else { return }

        guard inputPort.valueDidChange else { return }

        guard let boxed = inputPort.snapshotValue(),
              case .Array(let elements) = boxed,
              let first = elements.first else { return }

        outputPort.sendBoxed(first)
    }
}
