//
//  TweenNode.swift
//  Fabric
//

import Metal
import Satin

public final class TweenNode: NumericTypeAgnosticNode
{
    public override class var name: String { "Tween" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Numeric) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Tweens toward a target numeric value over time. Choose the value type in Settings." }
    public override class var supportedPortTypes: [PortType] { interpolatableSingleTypes + interpolatableArrayTypes }

    private var tween = TweenState()
    private var from: PortValue?
    private var to: PortValue?
    private var current: PortValue?

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputDuration", ParameterPort(parameter: FloatParameter("Duration", 1.0, .inputfield, "Tween duration in seconds"))),
            ("inputEasing", ParameterPort(parameter: StringParameter("Easing", "Linear", TweenEasing.titles, .dropdown, "Easing curve"))),
        ]
    }

    public var inputDuration: ParameterPort<Float> { _inputDuration }
    private var _inputDuration: ParameterPort<Float>!
    public var inputEasing: ParameterPort<String> { _inputEasing }
    private var _inputEasing: ParameterPort<String>!
    public var outputProgress: NodePort<Float> { _outputProgress }
    private var _outputProgress: NodePort<Float>!

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundInputTarget = findPort(named: "inputTarget")
        self.boundOutputValue = findPort(named: "outputValue")
        self._inputDuration = findPort(named: "inputDuration")
        self._inputEasing = findPort(named: "inputEasing")
        self._outputProgress = findPort(named: "outputProgress")
    }

    public override func declaredPorts() -> [PortDeclaration]
    {
        let portType = selectedNumericPortType

        return [
            PortDeclaration(key: "inputTarget", portType: portType, kind: .Inlet, name: "Target", description: "Target value"),
        ] + super.declaredPorts() + [
            PortDeclaration(key: "outputValue", portType: portType, kind: .Outlet, name: "Value", description: "Current tweened value"),
            PortDeclaration(key: "outputProgress", port: NodePort<Float>(name: "Progress", kind: .Outlet, description: "Tween progress (0-1)")),
        ]
    }

    public override func apply(_ settings: any NodeSettings)
    {
        super.apply(settings)
        from = nil
        to = nil
        current = nil
        tween = TweenState()
    }

    private var boundInputTarget: Port?
    private var boundOutputValue: Port?

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if specializeFromConnectedPort(self.boundInputTarget) { return }
        guard let inputTarget: Port = self.boundInputTarget,
              let outputValue: Port = self.boundOutputValue
        else { return }

        let time = executionInfo.timing.time
        if inputTarget.valueDidChange, let target = inputTarget.snapshotValue()
        {
            if current == nil
            {
                from = target
                to = target
                current = target
            }
            else if target != to
            {
                from = current
                to = target
                tween.start(at: time)
            }
        }

        guard let from, let to, let current else { return }
        let portType = selectedNumericPortType

        if let duration = inputDuration.value,
           let easingName = inputEasing.value,
           let result = tween.update(time: time, duration: duration, easingName: easingName)
        {
            let value: PortValue?
            if result.t >= 1.0
            {
                value = to
            }
            else if case .Array(let elementType) = portType,
                    let fromValues = NumericValueOperations.arrayValues(from: from),
                    let toValues = NumericValueOperations.arrayValues(from: to)
            {
                value = .Array(NumericValueOperations.interpolateArrays(fromValues, toValues, t: result.easedT, elementType: elementType))
            }
            else
            {
                value = NumericValueOperations.interpolate(from, to, t: result.easedT, as: portType)
            }

            self.current = value
            outputValue.sendBoxed(value)
            outputProgress.send(result.t)
        }
        else
        {
            outputValue.sendBoxed(current)
            outputProgress.send(tween.tweening ? 0.0 : 1.0)
        }
    }
}
