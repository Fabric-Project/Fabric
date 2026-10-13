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

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputOffset", ParameterPort(parameter: IntParameter("Offset", 0, .inputfield, "Starting index in the input array"))),
            ("inputCount",  ParameterPort(parameter: IntParameter("Count",  0, .inputfield, "Maximum number of elements to extract"))),
        ]
    }

    public var inputOffset: ParameterPort<Int> { port(named: "inputOffset") }
    public var inputCount:  ParameterPort<Int>  { port(named: "inputCount") }

    public override func declaredPorts() -> [PortDeclaration]
    {
        guard let elementType = PortType(rawValue: strategy) else { return super.declaredPorts() }

        let arrayType: PortType = .Array(portType: elementType)

        return [
            PortDeclaration(registryKey: "inputPort", portType: arrayType, kind: .Inlet, name: "Array", description: "Input array to subsample"),
        ] + super.declaredPorts() + [
            PortDeclaration(registryKey: "outputPort", portType: arrayType, kind: .Outlet, name: "Array", description: "Subarray extracted from the input"),
        ]
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
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
