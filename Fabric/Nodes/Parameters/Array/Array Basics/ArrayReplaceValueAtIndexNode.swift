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

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputIndexParam", ParameterPort(parameter: IntParameter("Index", 0, .inputfield, "Array index where the value will be replaced"))),
        ]
    }

    public var inputIndexParam: ParameterPort<Int> { port(named: "inputIndexParam") }

    public override func declaredPorts() -> [PortDeclaration]
    {
        guard let elementType = PortType(rawValue: strategy) else { return super.declaredPorts() }

        let arrayType: PortType = .Array(portType: elementType)

        return [
            PortDeclaration(registryKey: "inputPort", portType: arrayType, kind: .Inlet, name: "Array", description: "Input array to modify"),
        ] + super.declaredPorts() + [
            PortDeclaration(registryKey: "inputValue", portType: elementType, kind: .Inlet, name: "Value", description: "New value to insert at the specified index"),
            PortDeclaration(registryKey: "outputPort", portType: arrayType, kind: .Outlet, name: "Array", description: "Array with the value replaced at the specified index"),
        ]
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputPort:  Port = findPort(named: "inputPort"),
              let inputValue: Port = findPort(named: "inputValue"),
              let outputPort: Port = findPort(named: "outputPort") else { return }

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
