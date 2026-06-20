//
//  ArrayCountNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class ArrayCountNode: TypeAgnosticNode
{
    public override class var name: String { "Array Count" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Returns the number of elements in an array. Choose element type in Settings." }
    override public class var includesArrayTypesInStrategy: Bool { false }

    private static let dynamicPortNames: Set<String> = ["inputPort"]

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("outputPort", NodePort<Int>(name: "Count", kind: .Outlet, description: "Number of elements in the array")),
        ]
    }

    public var outputPort: NodePort<Int> { port(named: "outputPort") }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)
        guard let elementType = PortType(rawValue: strategy) else { return }

        let arrayType: PortType = elementType == .Virtual ? .Virtual : .Array(portType: elementType)

        if let existing: Port = findPort(named: "inputPort"), existing.portType != arrayType { removePort(existing) }
        if findPort(named: "inputPort") == nil {
            addDynamicPort(arrayType.makeFreshPort(name: "Array", kind: .Inlet, description: "Input array to count elements"), name: "inputPort")
        }

        let portOrder = ["inputPort", "outputPort"]
        let reordered: [Port] = portOrder.compactMap { name in let p: Port? = findPort(named: name); return p }
        if reordered.count == self.ports.count { reorderPorts(reordered) }
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard let inputPort: Port = findPort(named: "inputPort") else { return }
        guard inputPort.valueDidChange else { return }
        guard let boxed = inputPort.snapshotValue(),
              case .Array(let elements) = boxed else { return }
        outputPort.send(elements.count)
    }
}
