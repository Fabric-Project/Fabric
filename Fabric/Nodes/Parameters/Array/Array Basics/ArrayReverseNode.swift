//
//  ArrayReverseNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class ArrayReverseNode: TypeAgnosticNode
{
    public override class var name: String { "Array Reverse" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Reverses the element order of an array. Choose element type in Settings." }
    override public class var includesArrayTypesInStrategy: Bool { false }

    private static let dynamicPortNames: Set<String> = ["inputPort", "outputPort"]

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)
        guard let elementType = PortType(rawValue: strategy) else { return }

        let arrayType: PortType = .Array(portType: elementType)

        addOrReplaceDynamicPortPreservingIdentity(name: "inputPort", displayName: "Array", portType: arrayType, kind: .Inlet, description: "Input array")
        addOrReplaceDynamicPortPreservingIdentity(name: "outputPort", displayName: "Array", portType: arrayType, kind: .Outlet, description: "Reversed array")

        let portOrder = ["inputPort", "outputPort"]
        let reordered: [Port] = portOrder.compactMap { name in let p: Port? = findPort(named: name); return p }
        if reordered.count == self.ports.count { reorderPorts(reordered) }
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
              case .Array(let elements) = boxed else { return }

        outputPort.sendBoxed(.Array(ContiguousArray(elements.reversed())))
    }
}
