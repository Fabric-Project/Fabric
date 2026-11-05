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

    public let inputProgress = ParameterPort(parameter: FloatParameter("Progress", 0.0, 0.0, 1.0, .inputfield, "Manual interpolation progress"))
    public let inputEasing = ParameterPort(parameter: StringParameter("Easing", "Linear", TweenEasing.titles, .dropdown, "Easing curve"))

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundInputFrom = findPort(named: "inputFrom")
        self.boundInputTo = findPort(named: "inputTo")
        self.boundOutputValue = findPort(named: "outputValue")
    }

    public override func declaredPorts() -> [PortDeclaration]
    {
        let portType = selectedNumericPortType

        return [
            PortDeclaration(key: "inputFrom", portType: portType, kind: .Inlet, name: "From", description: "Start value"),
            PortDeclaration(key: "inputTo", portType: portType, kind: .Inlet, name: "To", description: "End value"),
        ] + super.declaredPorts() + [
            PortDeclaration(key: "inputProgress", port: self.inputProgress),
            PortDeclaration(key: "inputEasing", port: self.inputEasing),
            PortDeclaration(key: "outputValue", portType: portType, kind: .Outlet, name: "Value", description: "Interpolated value"),
        ]
    }

    private var boundInputFrom: Port?
    private var boundInputTo: Port?
    private var boundOutputValue: Port?

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputFrom: Port = self.boundInputFrom,
              let inputTo: Port = self.boundInputTo,
              let outputValue: Port = self.boundOutputValue,
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
