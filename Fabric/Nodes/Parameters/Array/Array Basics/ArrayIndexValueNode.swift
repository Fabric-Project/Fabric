//
//  ArrayIndexValueNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class ArrayIndexValueNode: TypeAgnosticNode
{
    public override class var name: String { "Array Value at Index" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Returns the element at the specified index. Choose element type in Settings." }
    override public class var includesArrayTypesInStrategy: Bool { false }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputIndexParam", ParameterPort(parameter: IntParameter("Index", 0, .inputfield, "Array index to retrieve the value from"))),
        ]
    }

    public var inputIndexParam: ParameterPort<Int> { port(named: "inputIndexParam") }

    public override func declaredPorts() -> [PortDeclaration]
    {
        guard let elementType = PortType(rawValue: strategy) else { return super.declaredPorts() }

        let arrayType: PortType = .Array(portType: elementType)

        return [
            PortDeclaration(registryKey: "inputPort", portType: arrayType, kind: .Inlet, name: "Array", description: "Input array to index into"),
        ] + super.declaredPorts() + [
            PortDeclaration(registryKey: "outputPort", portType: elementType, kind: .Outlet, name: "Value", description: "Element at the specified index"),
        ]
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputPort:  Port = findPort(named: "inputPort"),
              let outputPort: Port = findPort(named: "outputPort") else { return }

        guard inputPort.valueDidChange || inputIndexParam.valueDidChange else { return }

        guard
            let boxed = inputPort.snapshotValue(),
            case .Array(let elements) = boxed,
            let index = inputIndexParam.value
        else
        {
            outputPort.sendBoxed(nil)
            return
        }

        guard
            let val = elements.safeGet(index: max(0, index))
        else
        {
            outputPort.sendBoxed(nil)
            return
        }

        outputPort.sendBoxed(val)
    }
}
