//
//  PairwiseDistanceArrayNode.swift
//  Fabric
//

import Metal
import Satin

public final class PairwiseDistanceArrayNode: NumericTypeAgnosticNode
{
    public override class var name: String { "Pairwise Distance Array" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Numeric) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Computes one distance per pair of elements from two numeric arrays using zip-shortest." }
    public override class var supportedPortTypes: [PortType] { singleNumericTypes.map { .Array(portType: $0) } }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputMetric", metricParameter("Distance calculation method")),
            ("outputDistances", NodePort<ContiguousArray<Float>>(name: "Distances", kind: .Outlet, description: "Per-element distances"))
        ]
    }

    public var inputMetric: ParameterPort<String> { port(named: "inputMetric") }
    public var outputDistances: NodePort<ContiguousArray<Float>> { port(named: "outputDistances") }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)
        let portType = selectedNumericPortType

        addOrReplaceDynamicPort(name: "inputA", displayName: "A", portType: portType, kind: .Inlet, description: "First numeric array")
        addOrReplaceDynamicPort(name: "inputB", displayName: "B", portType: portType, kind: .Inlet, description: "Second numeric array")
        reorderPorts(named: ["inputA", "inputB", "inputMetric", "outputDistances"])
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
              case .Array(let elementType) = selectedNumericPortType,
              let valuesA = NumericValueOperations.arrayValues(from: inputA.snapshotValue()),
              let valuesB = NumericValueOperations.arrayValues(from: inputB.snapshotValue())
        else { return }

        let output = NumericValueOperations.distanceArrays(valuesA, valuesB, elementType: elementType, metric: currentMetric(from: inputMetric))
        outputDistances.sendBoxed(.Array(output))
    }
}
