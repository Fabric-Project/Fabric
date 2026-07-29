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

    public var inputMetric: ParameterPort<String> { port(named: "inputMetric") }
    public var outputDistance: NodePort<Float> { port(named: "outputDistance") }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)
        let portType = selectedNumericPortType

        addOrReplaceDynamicPort(name: "inputA", displayName: "A", portType: portType, kind: .Inlet, description: "First value", editable: true)
        addOrReplaceDynamicPort(name: "inputB", displayName: "B", portType: portType, kind: .Inlet, description: "Second value", editable: true)
        reorderPorts(named: ["inputA", "inputB", "inputMetric", "outputDistance"])
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if specializeFromConnectedPort(named: "inputA") || specializeFromConnectedPort(named: "inputB") { return }
        guard let inputA: Port = findPort(named: "inputA"),
              let inputB: Port = findPort(named: "inputB"),
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
