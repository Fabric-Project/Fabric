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

    public var inputCount: ParameterPort<Int> { _inputCount }
    private var _inputCount: ParameterPort<Int>!
    public var inputEasing: ParameterPort<String> { _inputEasing }
    private var _inputEasing: ParameterPort<String>!

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundInputFrom = findPort(named: "inputFrom")
        self.boundInputTo = findPort(named: "inputTo")
        self.boundOutputArray = findPort(named: "outputArray")
        self._inputCount = findPort(named: "inputCount")
        self._inputEasing = findPort(named: "inputEasing")
    }

    public override func declaredPorts() -> [PortDeclaration]
    {
        let valueType = selectedNumericPortType
        let arrayType: PortType = valueType == .NumericVirtual ? .NumericVirtual : .Array(portType: valueType)

        return [
            PortDeclaration(key: "inputFrom", portType: valueType, kind: .Inlet, name: "From", description: "Start value"),
            PortDeclaration(key: "inputTo", portType: valueType, kind: .Inlet, name: "To", description: "End value"),
        ] + super.declaredPorts() + [
            PortDeclaration(key: "outputArray", portType: arrayType, kind: .Outlet, name: "Array", description: "Generated interpolated values"),
        ]
    }

    private var boundInputFrom: Port?
    private var boundInputTo: Port?
    private var boundOutputArray: Port?

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if specializeFromConnectedPort(self.boundInputFrom) || specializeFromConnectedPort(self.boundInputTo) { return }
        guard let inputFrom: Port = self.boundInputFrom,
              let inputTo: Port = self.boundInputTo,
              let outputArray: Port = self.boundOutputArray,
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
