//
//  RepeatNode.swift
//  Fabric
//

import Metal
import Satin

public final class RepeatNode: NumericTypeAgnosticNode
{
    public override class var name: String { "Repeat" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Numeric) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Repeats one numeric value into an array. Choose the value type in Settings." }
    public override class var supportedPortTypes: [PortType] { singleNumericTypes }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputCount", ParameterPort(parameter: IntParameter("Count", 6, 0, 1024, .inputfield, "Number of elements")))
        ]
    }

    public var inputCount: ParameterPort<Int> { port(named: "inputCount") }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)
        let valueType = selectedNumericPortType
        let arrayType: PortType = valueType == .NumericVirtual ? .NumericVirtual : .Array(portType: valueType)
        addOrReplaceDynamicPort(name: "inputValue", displayName: "Value", portType: valueType, kind: .Inlet, description: "Value to repeat", editable: true)
        addOrReplaceDynamicPort(name: "outputArray", displayName: "Array", portType: arrayType, kind: .Outlet, description: "Repeated values")
        reorderPorts(named: ["inputValue", "inputCount", "outputArray"])
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if specializeFromConnectedPort(named: "inputValue") { return }
        guard let inputValue: Port = findPort(named: "inputValue"),
              let outputArray: Port = findPort(named: "outputArray"),
              inputValue.valueDidChange || inputCount.valueDidChange,
              let value = inputValue.snapshotValue(),
              let count = inputCount.value
        else { return }

        outputArray.sendBoxed(.Array(ContiguousArray(repeating: value, count: max(0, count))))
    }
}
