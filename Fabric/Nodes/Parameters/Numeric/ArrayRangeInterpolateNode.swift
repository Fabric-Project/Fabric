//
//  ArrayRangeInterpolateNode.swift
//  Fabric
//

import Metal
import Satin

public final class ArrayRangeInterpolateNode: NumericTypeAgnosticNode
{
    public override class var name: String { "Array Range Interpolate" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Numeric) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Generates an array interpolated from From to To using the selected easing function." }
    public override class var supportedPortTypes: [PortType] { interpolatableSingleTypes }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputCount", ParameterPort(parameter: IntParameter("Count", 6, 0, 1024, .inputfield, "Number of elements to generate"))),
            ("inputEasing", ParameterPort(parameter: StringParameter("Easing", "Linear", TweenEasing.titles, .dropdown, "Easing function applied to the interpolation")))
        ]
    }

    public var inputCount: ParameterPort<Int> { port(named: "inputCount") }
    public var inputEasing: ParameterPort<String> { port(named: "inputEasing") }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)
        let valueType = selectedNumericPortType
        let arrayType: PortType = valueType == .NumericVirtual ? .NumericVirtual : .Array(portType: valueType)
        addOrReplaceDynamicPort(name: "inputFrom", displayName: "From", portType: valueType, kind: .Inlet, description: "Start value", editable: true)
        addOrReplaceDynamicPort(name: "inputTo", displayName: "To", portType: valueType, kind: .Inlet, description: "End value", editable: true)
        addOrReplaceDynamicPort(name: "outputArray", displayName: "Array", portType: arrayType, kind: .Outlet, description: "Generated interpolated values")
        reorderPorts(named: ["inputFrom", "inputTo", "inputCount", "inputEasing", "outputArray"])
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if specializeFromConnectedPort(named: "inputFrom") || specializeFromConnectedPort(named: "inputTo") { return }
        guard let inputFrom: Port = findPort(named: "inputFrom"),
              let inputTo: Port = findPort(named: "inputTo"),
              let outputArray: Port = findPort(named: "outputArray"),
              inputFrom.valueDidChange || inputTo.valueDidChange || inputCount.valueDidChange || inputEasing.valueDidChange,
              let from = inputFrom.snapshotValue(),
              let to = inputTo.snapshotValue(),
              let count = inputCount.value,
              let easingName = inputEasing.value,
              let easing = TweenEasing.map[easingName]
        else { return }

        guard count > 0 else {
            outputArray.sendBoxed(.Array([]))
            return
        }

        guard count > 1 else {
            outputArray.sendBoxed(.Array([from]))
            return
        }

        let portType = selectedNumericPortType
        let divisor = Float(count - 1)
        var output = ContiguousArray<PortValue>()
        output.reserveCapacity(count)

        for index in 0..<count
        {
            let t = Float(index) / divisor
            let easedT = Float(easing.function(Double(t)))
            if let value = NumericValueOperations.interpolate(from, to, t: easedT, as: portType)
            {
                output.append(value)
            }
        }

        outputArray.sendBoxed(.Array(output))
    }
}
