//
//  SwitchNode.swift
//  Fabric
//

import Metal

public final class SwitchNode: RoutingNode
{
    override public class var name: String { "Switch" }
    override public class var nodeType: Node.NodeType { .Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Selects one input to route through. Inverse of Gate. Only the selected input branch is evaluated." }

    private static let outputPortName = "output"

    private static func inputPortName(_ index: Int) -> String
    {
        "input\(index)"
    }

    public var output: Port { _output }
    private var _output: Port!
    /// The route inlets, by route index.
    private var routeInputs: [Port] = []

    override public func bindPorts()
    {
        super.bindPorts()
        self._output = findPort(named: Self.outputPortName)
        self.routeInputs = (0..<routeCount).compactMap { findPort(named: Self.inputPortName($0)) }
    }

    private func routeInput(_ index: Int) -> Port?
    {
        routeInputs.indices.contains(index) ? routeInputs[index] : nil
    }

    public override func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts()
            + (0..<routeCount).map { index in
                routePortDeclaration(key: Self.inputPortName(index),
                                     name: "Input \(index)",
                                     kind: .Inlet,
                                     description: "Value for route \(index)")
            }
            + [routePortDeclaration(key: Self.outputPortName,
                                    name: "Output",
                                    kind: .Outlet,
                                    description: "Selected input value")]
    }

    public override func respondToPull(requestedOutputPort: Port?) -> Node.PullResponse
    {
        let routeIndex = selectedRouteIndex()

        guard let selectedInput = routeInput(routeIndex)
        else { return .evaluate(pulling: [inputIndex]) }

        return .evaluate(pulling: [inputIndex, selectedInput])
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let selectedInput = routeInput(selectedRouteIndex())
        else { return }

        output.sendBoxed(selectedInput.snapshotValue(), force: true)
    }

    public override func updateConnectionTopology()
    {
        graph?.setConnections(from: inputIndex, active: true)

        let selected = selectedRouteIndex()
        for (index, inputPort) in routeInputs.enumerated()
        {
            graph?.setConnections(from: inputPort, active: index == selected)
        }
    }
}
