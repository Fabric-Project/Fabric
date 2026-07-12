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

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputCount", ParameterPort(parameter: IntParameter("Count", 6, 0, 1024, .inputfield, "Desired output element count")))
        ]
    }

    public var inputCount: ParameterPort<Int> { port(named: "inputCount") }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)
        let portType = selectedNumericPortType
        addOrReplaceDynamicPort(name: "inputArray", displayName: "Array", portType: portType, kind: .Inlet, description: "Source array")
        addOrReplaceDynamicPort(name: "outputArray", displayName: "Array", portType: portType, kind: .Outlet, description: "Resampled array")
        reorderPorts(named: ["inputArray", "inputCount", "outputArray"])
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if specializeFromConnectedPort(named: "inputArray") { return }
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
