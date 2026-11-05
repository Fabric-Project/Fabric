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
        guard let elementType = strategy as? PortType else { return super.declaredPorts() }

        let arrayType: PortType = .Array(portType: elementType)

        return [
            PortDeclaration(key: "inputArrayA", portType: arrayType, kind: .Inlet, name: "Array A", description: "First array"),
            PortDeclaration(key: "inputArrayB", portType: arrayType, kind: .Inlet, name: "Array B", description: "Second array, appended after Array A"),
            PortDeclaration(key: "outputPort", portType: arrayType, kind: .Outlet, name: "Array", description: "Concatenated array"),
        ] + super.declaredPorts()
    }

    private var boundInputArrayA: Port?
    private var boundInputArrayB: Port?
    private var boundOutputPort: Port?

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundInputArrayA = findPort(named: "inputArrayA")
        self.boundInputArrayB = findPort(named: "inputArrayB")
        self.boundOutputPort = findPort(named: "outputPort")
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputPortA: Port = self.boundInputArrayA,
              let inputPortB: Port = self.boundInputArrayB,
              let outputPort: Port = self.boundOutputPort else { return }

        guard inputPortA.valueDidChange || inputPortB.valueDidChange else { return }

        let a: ContiguousArray<PortValue>
        if let boxed = inputPortA.snapshotValue(), case .Array(let elems) = boxed { a = elems } else { a = [] }

        let b: ContiguousArray<PortValue>
        if let boxed = inputPortB.snapshotValue(), case .Array(let elems) = boxed { b = elems } else { b = [] }

        outputPort.sendBoxed(.Array(a + b))
    }
}
