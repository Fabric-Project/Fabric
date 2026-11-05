//
//  GateNode.swift
//  Fabric
//

import Metal

public final class GateNode: RoutingNode
{
    override public class var name: String { "Gate" }
    override public class var nodeType: Node.NodeType { .Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Routes one input to one selected output. Inverse of Switch. Only the selected output branch is evaluated; consumers of unselected branches will see the value freeze." }

    private static let inputPortName = "input"
    private var activeRouteIndex: Int?

    private static func outputPortName(_ index: Int) -> String
    {
        "output\(index)"
    }

    public var input: Port { _input }
    private var _input: Port!
    /// The route outlets, by route index.
    private var routeOutputs: [Port] = []

    override public func bindPorts()
    {
        super.bindPorts()
        self._input = findPort(named: Self.inputPortName)
        self.routeOutputs = (0..<routeCount).compactMap { findPort(named: Self.outputPortName($0)) }
    }

    public override func respondToPull(requestedOutputPort: Port?) -> Node.PullResponse
    {
        if let requestedOutputPort, requestedOutputPort.id != selectedOutputPort()?.id
        {
            // Unselected branch: nothing to contribute, but a connected Index
            // must keep updating so the gate can switch routes.
            return .declined(keepAlive: [inputIndex])
        }

        return .evaluate(pulling: [inputIndex, input])
    }

    public override func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts()
            + [routePortDeclaration(key: Self.inputPortName,
                                    name: "Input",
                                    kind: .Inlet,
                                    description: "Value to route")]
            + (0..<routeCount).map { index in
                routePortDeclaration(key: Self.outputPortName(index),
                                     name: "Output \(index)",
                                     kind: .Outlet,
                                     description: "Value when route \(index) is selected")
            }
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        selectedOutputPort()?.sendBoxed(input.snapshotValue(), force: true)
    }

    private func selectedOutputPort() -> Port?
    {
        let index = selectedRouteIndex()
        return routeOutputs.indices.contains(index) ? routeOutputs[index] : nil
    }

    public override func updateConnectionTopology()
    {
        graph?.setConnections(from: inputIndex, active: true)
        if let input = _input
        {
            graph?.setConnections(from: input, active: true)
        }

        let routeIndex = selectedRouteIndex()
        guard activeRouteIndex != routeIndex else { return }

        activeRouteIndex = routeIndex
        graph?.markExecutionTopologyChanged()
    }
}
