//
//  ArrayResampleTypeAgnosticNode.swift
//  Fabric
//

import Metal
import Satin

public final class ArrayResampleTypeAgnosticNode: NumericTypeAgnosticNode
{
    public override class var name: String { "Array Resample" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Numeric) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Resamples a numeric array to a new count using type-appropriate interpolation." }
    public override class var supportedPortTypes: [PortType] { interpolatableArrayTypes }
    public override class var specializingInletNames: [String] { ["inputArray"] }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputCount", ParameterPort(parameter: IntParameter("Count", 6, 0, 1024, .inputfield, "Desired output element count")))
        ]
    }

    public var inputCount: ParameterPort<Int> { port(named: "inputCount") }

    public override func declaredPorts() -> [PortDeclaration]
    {
        let portType = selectedNumericPortType

        return [
            PortDeclaration(registryKey: "inputArray", portType: portType, kind: .Inlet, name: "Array", description: "Source array"),
        ] + super.declaredPorts() + [
            PortDeclaration(registryKey: "outputArray", portType: portType, kind: .Outlet, name: "Array", description: "Resampled array"),
        ]
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if specializeFromConnectedInlets() { return }
        guard let inputArray: Port = findPort(named: "inputArray"),
              let outputArray: Port = findPort(named: "outputArray"),
              inputArray.valueDidChange || inputCount.valueDidChange,
              case .Array(let elementType) = selectedNumericPortType,
              let source = NumericValueOperations.arrayValues(from: inputArray.snapshotValue()),
              let count = inputCount.value
        else { return }

        outputArray.sendBoxed(.Array(NumericValueOperations.resampleArray(source, count: count, elementType: elementType)))
    }
}
