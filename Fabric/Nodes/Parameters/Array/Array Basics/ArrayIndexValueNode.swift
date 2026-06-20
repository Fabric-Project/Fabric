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

    private static let dynamicPortNames: Set<String> = ["inputPort", "outputPort"]

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputIndexParam", ParameterPort(parameter: IntParameter("Index", 0, .inputfield, "Array index to retrieve the value from"))),
        ]
    }

    public var inputIndexParam: ParameterPort<Int> { port(named: "inputIndexParam") }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)
        guard let elementType = PortType(rawValue: strategy) else { return }

        let arrayType: PortType = elementType == .Virtual ? .Virtual : .Array(portType: elementType)

        if let existing: Port = findPort(named: "inputPort"),  existing.portType != arrayType   { removePort(existing) }
        if let existing: Port = findPort(named: "outputPort"), existing.portType != elementType { removePort(existing) }
        if findPort(named: "inputPort") == nil {
            addDynamicPort(arrayType.makeFreshPort(name: "Array", kind: .Inlet,  description: "Input array to index into"), name: "inputPort")
        }
        if findPort(named: "outputPort") == nil {
            addDynamicPort(elementType.makeFreshPort(name: "Value", kind: .Outlet, description: "Element at the specified index"), name: "outputPort")
        }

        let portOrder = ["inputPort", "inputIndexParam", "outputPort"]
        let reordered: [Port] = portOrder.compactMap { name in let p: Port? = findPort(named: name); return p }
        if reordered.count == self.ports.count { reorderPorts(reordered) }
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard let inputPort:  Port = findPort(named: "inputPort"),
              let outputPort: Port = findPort(named: "outputPort") else { return }

        guard inputPort.valueDidChange || inputIndexParam.valueDidChange else { return }

        guard let boxed = inputPort.snapshotValue(),
              case .Array(let elements) = boxed,
              let index = inputIndexParam.value else { return }

        if let val = elements.safeGet(index: max(0, index)) {
            outputPort.sendBoxed(val)
        }
    }
}
