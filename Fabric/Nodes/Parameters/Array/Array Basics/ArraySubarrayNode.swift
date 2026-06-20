//
//  ArraySubarrayNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class ArraySubarrayNode: TypeAgnosticNode
{
    public override class var name: String { "Array Subarray" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Extracts a subset of an array by offset and count. No new elements are synthesized; if offset is beyond the array bounds the output is empty. Choose element type in Settings." }
    override public class var includesArrayTypesInStrategy: Bool { false }

    private static let dynamicPortNames: Set<String> = ["inputPort", "outputPort"]

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputOffset", ParameterPort(parameter: IntParameter("Offset", 0, .inputfield, "Starting index in the input array"))),
            ("inputCount",  ParameterPort(parameter: IntParameter("Count",  0, .inputfield, "Maximum number of elements to extract"))),
        ]
    }

    public var inputOffset: ParameterPort<Int> { port(named: "inputOffset") }
    public var inputCount:  ParameterPort<Int>  { port(named: "inputCount") }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)
        guard let elementType = PortType(rawValue: strategy) else { return }

        let arrayType: PortType = elementType == .Virtual ? .Virtual : .Array(portType: elementType)

        for name in ["inputPort", "outputPort"] {
            if let p: Port = findPort(named: name), p.portType != arrayType { removePort(p) }
        }
        if findPort(named: "inputPort") == nil {
            addDynamicPort(arrayType.makeFreshPort(name: "Array", kind: .Inlet,  description: "Input array to subsample"), name: "inputPort")
        }
        if findPort(named: "outputPort") == nil {
            addDynamicPort(arrayType.makeFreshPort(name: "Array", kind: .Outlet, description: "Subarray extracted from the input"), name: "outputPort")
        }

        let portOrder = ["inputPort", "inputOffset", "inputCount", "outputPort"]
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

        guard inputPort.valueDidChange || inputOffset.valueDidChange || inputCount.valueDidChange else { return }

        guard let boxed = inputPort.snapshotValue(),
              case .Array(let elements) = boxed,
              let offset = inputOffset.value,
              let count  = inputCount.value
        else
        {
            outputPort.sendBoxed(.Array(ContiguousArray()))
            return
        }

        if offset >= elements.count
        {
            outputPort.sendBoxed(.Array(ContiguousArray()))
            return
        }

        outputPort.sendBoxed(.Array(ContiguousArray(elements.dropFirst(offset).prefix(count))))
    }
}
