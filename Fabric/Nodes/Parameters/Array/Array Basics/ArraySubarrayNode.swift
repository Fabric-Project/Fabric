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

    public var inputOffset: ParameterPort<Int> { _inputOffset }
    private var _inputOffset: ParameterPort<Int>!
    public var inputCount: ParameterPort<Int> { _inputCount }
    private var _inputCount: ParameterPort<Int>!

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundInputPort = findPort(named: "inputPort")
        self.boundOutputPort = findPort(named: "outputPort")
        self._inputOffset = findPort(named: "inputOffset")
        self._inputCount = findPort(named: "inputCount")
    }

    public override func declaredPorts() -> [PortDeclaration]
    {
        guard let elementType = strategy as? PortType else { return super.declaredPorts() }

        let arrayType: PortType = .Array(portType: elementType)

        return [
            PortDeclaration(key: "inputPort", portType: arrayType, kind: .Inlet, name: "Array", description: "Input array to subsample"),
        ] + super.declaredPorts() + [
            PortDeclaration(key: "outputPort", portType: arrayType, kind: .Outlet, name: "Array", description: "Subarray extracted from the input"),
        ]
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
