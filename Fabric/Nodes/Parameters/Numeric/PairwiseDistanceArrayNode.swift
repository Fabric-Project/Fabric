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

    public let inputMetric: ParameterPort<String> = metricParameter("Distance calculation method")
    public let outputDistances = NodePort<ContiguousArray<Float>>(name: "Distances", kind: .Outlet, description: "Per-element distances")

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
            PortDeclaration(key: "inputA", portType: portType, kind: .Inlet, name: "A", description: "First numeric array"),
            PortDeclaration(key: "inputB", portType: portType, kind: .Inlet, name: "B", description: "Second numeric array"),
        ] + super.declaredPorts() + [
            PortDeclaration(key: "inputMetric", port: self.inputMetric),
            PortDeclaration(key: "outputDistances", port: self.outputDistances),
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
              case .Array(let elementType) = selectedNumericPortType,
              let valuesA = NumericValueOperations.arrayValues(from: inputA.snapshotValue()),
              let valuesB = NumericValueOperations.arrayValues(from: inputB.snapshotValue())
        else { return }

        let output = NumericValueOperations.distanceArrays(valuesA, valuesB, elementType: elementType, metric: currentMetric(from: inputMetric))
        outputDistances.sendBoxed(.Array(output))
    }
}
