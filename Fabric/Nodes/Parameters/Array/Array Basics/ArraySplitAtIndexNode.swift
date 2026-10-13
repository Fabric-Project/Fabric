//
//  ArraySplitAtIndexNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class ArraySplitAtIndexNode: TypeAgnosticNode
{
    public override class var name: String { "Array Split at Index" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Splits an array at Index into two: elements before the index and elements from the index onward. Choose element type in Settings." }
    override public class var includesArrayTypesInStrategy: Bool { false }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputIndex", ParameterPort(parameter: IntParameter("Index", 0, .inputfield, "Split position; elements before this index go to Before, elements from this index onward go to From"))),
        ]
    }

    public var inputIndex: ParameterPort<Int> { port(named: "inputIndex") }

    public override func declaredPorts() -> [PortDeclaration]
    {
        guard let elementType = PortType(rawValue: strategy) else { return super.declaredPorts() }

        let arrayType: PortType = .Array(portType: elementType)

        return [
            PortDeclaration(registryKey: "inputPort", portType: arrayType, kind: .Inlet, name: "Array", description: "Input array to split"),
        ] + super.declaredPorts() + [
            PortDeclaration(registryKey: "outputBefore", portType: arrayType, kind: .Outlet, name: "Before", description: "Elements at indices 0 ..< Index"),
            PortDeclaration(registryKey: "outputFrom", portType: arrayType, kind: .Outlet, name: "From", description: "Elements at indices Index ..< count"),
        ]
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputPort:    Port = findPort(named: "inputPort"),
              let outputBefore: Port = findPort(named: "outputBefore"),
              let outputFrom:   Port = findPort(named: "outputFrom") else { return }

        guard inputPort.valueDidChange || inputIndex.valueDidChange else { return }

        guard let boxed = inputPort.snapshotValue(),
              case .Array(let elements) = boxed,
              let index = inputIndex.value
        else
        {
            outputBefore.sendBoxed(.Array(ContiguousArray()))
            outputFrom.sendBoxed(.Array(ContiguousArray()))
            return
        }

        let clamped = max(0, min(index, elements.count))
        outputBefore.sendBoxed(.Array(ContiguousArray(elements[0..<clamped])))
        outputFrom.sendBoxed(.Array(ContiguousArray(elements[clamped...])))
    }
}
