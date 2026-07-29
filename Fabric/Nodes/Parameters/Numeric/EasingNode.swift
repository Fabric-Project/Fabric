//
//  EasingNode.swift
//  Fabric
//

import Metal
import Satin

public final class EasingNode: NumericTypeAgnosticNode
{
    public override class var name: String { "Easing" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Numeric) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Interpolates between two numeric values using a manually driven easing progress." }
    public override class var supportedPortTypes: [PortType] { interpolatableSingleTypes + interpolatableArrayTypes }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputProgress", ParameterPort(parameter: FloatParameter("Progress", 0.0, 0.0, 1.0, .inputfield, "Manual interpolation progress"))),
            ("inputEasing", ParameterPort(parameter: StringParameter("Easing", "Linear", TweenEasing.titles, .dropdown, "Easing curve")))
        ]
    }

    public var inputProgress: ParameterPort<Float> { port(named: "inputProgress") }
    public var inputEasing: ParameterPort<String> { port(named: "inputEasing") }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)
        let portType = selectedNumericPortType
        addOrReplaceDynamicPort(name: "inputFrom", displayName: "From", portType: portType, kind: .Inlet, description: "Start value", editable: true)
        addOrReplaceDynamicPort(name: "inputTo", displayName: "To", portType: portType, kind: .Inlet, description: "End value", editable: true)
        addOrReplaceDynamicPort(name: "outputValue", displayName: "Value", portType: portType, kind: .Outlet, description: "Interpolated value")
        reorderPorts(named: ["inputFrom", "inputTo", "inputProgress", "inputEasing", "outputValue"])
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
              let outputValue: Port = findPort(named: "outputValue"),
              inputFrom.valueDidChange || inputTo.valueDidChange || inputProgress.valueDidChange || inputEasing.valueDidChange,
              let from = inputFrom.snapshotValue(),
              let to = inputTo.snapshotValue(),
              let progress = inputProgress.value,
              let easingName = inputEasing.value,
              let easing = TweenEasing.map[easingName]
        else { return }

        let easedT = Float(easing.function(Double(min(max(progress, 0), 1))))
        let portType = selectedNumericPortType
        let value: PortValue?

        if case .Array(let elementType) = portType,
           let fromValues = NumericValueOperations.arrayValues(from: from),
           let toValues = NumericValueOperations.arrayValues(from: to)
        {
            value = .Array(NumericValueOperations.interpolateArrays(fromValues, toValues, t: easedT, elementType: elementType))
        }
        else
        {
            value = NumericValueOperations.interpolate(from, to, t: easedT, as: portType)
        }

        outputValue.sendBoxed(value)
    }
}
