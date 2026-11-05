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

    public let inputMetric: ParameterPort<String> = metricParameter("Distance calculation method")
    public let outputDistance = NodePort<Float>(name: "Distance", kind: .Outlet, description: "Calculated distance")

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundInputA = findPort(named: "inputA")
        self.boundInputB = findPort(named: "inputB")
    }

    public override func declaredPorts() -> [PortDeclaration]
    {
        let portType = selectedNumericPortType

        return [
            PortDeclaration(key: "inputA", portType: portType, kind: .Inlet, name: "A", description: "First value"),
            PortDeclaration(key: "inputB", portType: portType, kind: .Inlet, name: "B", description: "Second value"),
        ] + super.declaredPorts() + [
            PortDeclaration(key: "inputMetric", port: self.inputMetric),
            PortDeclaration(key: "outputDistance", port: self.outputDistance),
        ]
    }

    private var boundInputA: Port?
    private var boundInputB: Port?

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
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
