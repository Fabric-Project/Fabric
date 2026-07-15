//
//  ArrayQueueNode.swift
//  Fabric
//
//  Created by Anton Marini on 9/19/25.
//

import Foundation
import Satin
import simd
import Metal
import MetalKit

public class ArrayQueueNode: TypeAgnosticNode
{
    public override class var name: String { "Array Queue Value" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Inserts items into the beginning of an array queue. Choose element type in Settings." }
    override public class var includesArrayTypesInStrategy: Bool { false }

    private static let dynamicPortNames: Set<String> = ["inputPort", "outputPort"]

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputSizeParam", ParameterPort(parameter: IntParameter("Size", 0, .inputfield, "Maximum number of elements to keep in the queue"))),
            ("resetPort",     ParameterPort(parameter: BoolParameter("Reset", false, .button,  "When true, drops all queued items while maintaining capacity")))
        ]
    }

    public var inputSizeParam: ParameterPort<Int> { port(named: "inputSizeParam") }
    public var resetPort: NodePort<Bool>           { port(named: "resetPort") }

    // Type-agnostic queue; PortValue boxing lets this work identically for Virtual and typed ports.
    private var queue: ContiguousArray<PortValue> = []

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)
        guard let elementType = PortType(rawValue: strategy) else { return }

        let arrayType: PortType = .Array(portType: elementType)

        addOrReplaceDynamicPortPreservingIdentity(name: "inputPort", displayName: "Value", portType: elementType, kind: .Inlet, description: "Value to insert at the front of the queue")
        addOrReplaceDynamicPortPreservingIdentity(name: "outputPort", displayName: "Array", portType: arrayType, kind: .Outlet, description: "Array containing the queued values")

        queue.removeAll()

        let portOrder = ["inputPort", "inputSizeParam", "resetPort", "outputPort"]
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

        if resetPort.valueDidChange, resetPort.value == true
        {
            queue.removeAll(keepingCapacity: true)
            outputPort.sendBoxed(.Array(queue))
            return
        }

        if inputSizeParam.valueDidChange, let size = inputSizeParam.value
        {
            queue = ContiguousArray(queue.prefix(size))
        }

        if inputPort.valueDidChange,
           let value = inputPort.snapshotValue(),
           let size  = inputSizeParam.value
        {
            queue.insert(value, at: 0)
            queue = ContiguousArray(queue.prefix(size))
            outputPort.sendBoxed(.Array(queue))
        }
    }
}
