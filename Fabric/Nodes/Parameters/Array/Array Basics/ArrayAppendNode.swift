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

    private static let dynamicPortNames: Set<String> = ["inputArrayA", "inputArrayB", "outputPort"]

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)
        guard let elementType = PortType(rawValue: strategy) else { return }

        let arrayType: PortType = .Array(portType: elementType)

        for name in ["inputArrayA", "inputArrayB", "outputPort"] {
            if let p: Port = findPort(named: name), p.portType != arrayType { removePort(p) }
        }
        if findPort(named: "inputArrayA") == nil {
            addDynamicPort(arrayType.makeFreshPort(name: "Array A", kind: .Inlet,  description: "First array"), name: "inputArrayA")
        }
        if findPort(named: "inputArrayB") == nil {
            addDynamicPort(arrayType.makeFreshPort(name: "Array B", kind: .Inlet,  description: "Second array, appended after Array A"), name: "inputArrayB")
        }
        if findPort(named: "outputPort") == nil {
            addDynamicPort(arrayType.makeFreshPort(name: "Array",   kind: .Outlet, description: "Concatenated array"), name: "outputPort")
        }

        let portOrder = ["inputArrayA", "inputArrayB", "outputPort"]
        let reordered: [Port] = portOrder.compactMap { name in let p: Port? = findPort(named: name); return p }
        if reordered.count == self.ports.count { reorderPorts(reordered) }
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
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
