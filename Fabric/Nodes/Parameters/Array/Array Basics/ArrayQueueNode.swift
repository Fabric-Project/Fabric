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

    public let inputSizeParam = ParameterPort(parameter: IntParameter("Size", 0, .inputfield, "Maximum number of elements to keep in the queue"))
    public let resetPort: NodePort<Bool> = ParameterPort(parameter: BoolParameter("Reset", false, .button,  "When true, drops all queued items while maintaining capacity"))

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundInputPort = findPort(named: "inputPort")
        self.boundOutputPort = findPort(named: "outputPort")
    }

    // Type-agnostic queue; PortValue boxing lets this work identically for Virtual and typed ports.
    private var queue: ContiguousArray<PortValue> = []

    public override func declaredPorts() -> [PortDeclaration]
    {
        let storedPorts = [
            PortDeclaration(key: "inputSizeParam", port: self.inputSizeParam),
            PortDeclaration(key: "resetPort", port: self.resetPort),
        ]

        guard let elementType = strategy as? PortType else { return super.declaredPorts() + storedPorts }

        let arrayType: PortType = .Array(portType: elementType)

        return [
            PortDeclaration(key: "inputPort", portType: elementType, kind: .Inlet, name: "Value", description: "Value to insert at the front of the queue"),
        ] + super.declaredPorts() + storedPorts + [
            PortDeclaration(key: "outputPort", portType: arrayType, kind: .Outlet, name: "Array", description: "Array containing the queued values"),
        ]
    }

    public override func apply(_ settings: any NodeSettings)
    {
        super.apply(settings)
        queue.removeAll()
    }

    private var boundInputPort: Port?
    private var boundOutputPort: Port?

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputPort:  Port = self.boundInputPort,
              let outputPort: Port = self.boundOutputPort else { return }

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
