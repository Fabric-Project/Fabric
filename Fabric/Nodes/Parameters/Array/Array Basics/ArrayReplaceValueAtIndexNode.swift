//
//  ArrayReplaceValueAtIndexNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class ArrayReplaceValueAtIndexNode: TypeAgnosticNode
{
    public override class var name: String { "Array Replace Value at Index" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Replaces the element at the specified index with a new value. Choose element type in Settings." }
    override public class var includesArrayTypesInStrategy: Bool { false }

    public let inputIndexParam = ParameterPort(parameter: IntParameter("Index", 0, .inputfield, "Array index where the value will be replaced"))

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundInputPort = findPort(named: "inputPort")
        self.boundInputValue = findPort(named: "inputValue")
        self.boundOutputPort = findPort(named: "outputPort")
    }

    public override func declaredPorts() -> [PortDeclaration]
    {
        let storedPorts = [
            PortDeclaration(key: "inputIndexParam", port: self.inputIndexParam),
        ]

        guard let elementType = strategy as? PortType else { return super.declaredPorts() + storedPorts }

        let arrayType: PortType = .Array(portType: elementType)

        return [
            PortDeclaration(key: "inputPort", portType: arrayType, kind: .Inlet, name: "Array", description: "Input array to modify"),
        ] + super.declaredPorts() + storedPorts + [
            PortDeclaration(key: "inputValue", portType: elementType, kind: .Inlet, name: "Value", description: "New value to insert at the specified index"),
            PortDeclaration(key: "outputPort", portType: arrayType, kind: .Outlet, name: "Array", description: "Array with the value replaced at the specified index"),
        ]
    }

    private var boundInputPort: Port?
    private var boundInputValue: Port?
    private var boundOutputPort: Port?

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputPort:  Port = self.boundInputPort,
              let inputValue: Port = self.boundInputValue,
              let outputPort: Port = self.boundOutputPort else { return }

        guard inputPort.valueDidChange || inputIndexParam.valueDidChange || inputValue.valueDidChange else { return }

        guard let boxed = inputPort.snapshotValue(),
              case .Array(var elements) = boxed,
              let index = inputIndexParam.value,
              let replacement = inputValue.snapshotValue() else { return }

        if index >= 0 && index < elements.count {
            elements[index] = replacement
        }

        outputPort.sendBoxed(.Array(elements))
    }
}
