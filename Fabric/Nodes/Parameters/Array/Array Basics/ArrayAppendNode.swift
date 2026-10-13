//
//  ArrayAppendNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class ArrayAppendNode: TypeAgnosticNode
{
    public override class var name: String { "Array Append" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Appends Array B onto the end of Array A, producing a single concatenated array. Choose element type in Settings." }
    override public class var includesArrayTypesInStrategy: Bool { false }

    public override func declaredPorts() -> [PortDeclaration]
    {
        guard let elementType = PortType(rawValue: strategy) else { return super.declaredPorts() }

        let arrayType: PortType = .Array(portType: elementType)

        return [
            PortDeclaration(registryKey: "inputArrayA", portType: arrayType, kind: .Inlet, name: "Array A", description: "First array"),
            PortDeclaration(registryKey: "inputArrayB", portType: arrayType, kind: .Inlet, name: "Array B", description: "Second array, appended after Array A"),
            PortDeclaration(registryKey: "outputPort", portType: arrayType, kind: .Outlet, name: "Array", description: "Concatenated array"),
        ] + super.declaredPorts()
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputPortA: Port = findPort(named: "inputArrayA"),
              let inputPortB: Port = findPort(named: "inputArrayB"),
              let outputPort: Port = findPort(named: "outputPort") else { return }

        guard inputPortA.valueDidChange || inputPortB.valueDidChange else { return }

        let a: ContiguousArray<PortValue>
        if let boxed = inputPortA.snapshotValue(), case .Array(let elems) = boxed { a = elems } else { a = [] }

        let b: ContiguousArray<PortValue>
        if let boxed = inputPortB.snapshotValue(), case .Array(let elems) = boxed { b = elems } else { b = [] }

        outputPort.sendBoxed(.Array(a + b))
    }
}
