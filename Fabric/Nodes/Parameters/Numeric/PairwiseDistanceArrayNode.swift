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

    public var inputMetric: ParameterPort<String> { _inputMetric }
    private var _inputMetric: ParameterPort<String>!
    public var outputDistances: NodePort<ContiguousArray<Float>> { _outputDistances }
    private var _outputDistances: NodePort<ContiguousArray<Float>>!

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundInputA = findPort(named: "inputA")
        self.boundInputB = findPort(named: "inputB")
        self._inputMetric = findPort(named: "inputMetric")
        self._outputDistances = findPort(named: "outputDistances")
    }

    public override func declaredPorts() -> [PortDeclaration]
    {
        let portType = selectedNumericPortType

        return [
            PortDeclaration(key: "inputA", portType: portType, kind: .Inlet, name: "A", description: "First numeric array"),
            PortDeclaration(key: "inputB", portType: portType, kind: .Inlet, name: "B", description: "Second numeric array"),
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
              case .Array(let elementType) = selectedNumericPortType,
              let valuesA = NumericValueOperations.arrayValues(from: inputA.snapshotValue()),
              let valuesB = NumericValueOperations.arrayValues(from: inputB.snapshotValue())
        else { return }

        let output = NumericValueOperations.distanceArrays(valuesA, valuesB, elementType: elementType, metric: currentMetric(from: inputMetric))
        outputDistances.sendBoxed(.Array(output))
    }
}
