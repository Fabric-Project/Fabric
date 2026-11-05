//
//  DistanceNode.swift
//  Fabric
//

import Metal
import Satin

public final class DistanceNode: NumericTypeAgnosticNode
{
    public override class var name: String { "Distance" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Numeric) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Computes a domain-aware distance between two numeric values. Choose the value type in Settings." }
    public override class var supportedPortTypes: [PortType] { singleNumericTypes }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputMetric", metricParameter("Distance calculation method")),
            ("outputDistance", NodePort<Float>(name: "Distance", kind: .Outlet, description: "Calculated distance"))
        ]
    }

    public var inputMetric: ParameterPort<String> { _inputMetric }
    private var _inputMetric: ParameterPort<String>!
    public var outputDistance: NodePort<Float> { _outputDistance }
    private var _outputDistance: NodePort<Float>!

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundInputA = findPort(named: "inputA")
        self.boundInputB = findPort(named: "inputB")
        self._inputMetric = findPort(named: "inputMetric")
        self._outputDistance = findPort(named: "outputDistance")
    }

    public override func declaredPorts() -> [PortDeclaration]
    {
        let portType = selectedNumericPortType

        return [
            PortDeclaration(key: "inputA", portType: portType, kind: .Inlet, name: "A", description: "First value"),
            PortDeclaration(key: "inputB", portType: portType, kind: .Inlet, name: "B", description: "Second value"),
        ] + super.declaredPorts()
    }

    private var boundInputA: Port?
    private var boundInputB: Port?

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if specializeFromConnectedPort(self.boundInputA) || specializeFromConnectedPort(self.boundInputB) { return }
        guard let inputA: Port = self.boundInputA,
              let inputB: Port = self.boundInputB,
              inputA.valueDidChange || inputB.valueDidChange || inputMetric.valueDidChange,
              let valueA = inputA.snapshotValue(),
              let valueB = inputB.snapshotValue()
        else { return }

        let portType = selectedNumericPortType
        guard portType != .NumericVirtual,
              let distance = NumericValueOperations.distance(valueA, valueB, as: portType, metric: currentMetric(from: inputMetric))
        else { return }

        outputDistance.send(distance)
    }
}
