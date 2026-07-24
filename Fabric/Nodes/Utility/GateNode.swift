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

    private static func outputPortName(_ index: Int) -> String
    {
        "output\(index)"
    }

    public var input: Port { port(named: Self.inputPortName) }

    public override func shouldEvaluate(requestedOutputPort: Port?) -> Bool
    {
        guard let requestedOutputPort else { return true }
        return requestedOutputPort.id == selectedOutputPort()?.id
    }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)
        let portType = PortType(rawValue: strategy) ?? .Virtual

        addOrReplaceDynamicPortPreservingIdentity(name: Self.inputPortName,
                                                  displayName: "Input",
                                                  portType: portType,
                                                  kind: .Inlet,
                                                  description: "Value to route")

        for index in 0..<routeCount
        {
            addOrReplaceDynamicPortPreservingIdentity(name: Self.outputPortName(index),
                                                      displayName: "Output \(index)",
                                                      portType: portType,
                                                      kind: .Outlet,
                                                      description: "Value when route \(index) is selected")
        }

        removeRoutingPortsAboveRouteCount(named: Self.outputPortName)

        let orderedPortNames = ["inputIndex", Self.inputPortName] + (0..<routeCount).map(Self.outputPortName)
        applyPortOrder(orderedPortNames)
    }

    public override func activeInputPorts(requestedOutputPort: Port?) -> [Port]
    {
        guard shouldEvaluate(requestedOutputPort: requestedOutputPort) else { return [] }
        return [inputIndex, input]
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        selectedOutputPort()?.sendBoxed(input.snapshotValue(), force: true)
    }

    private func selectedOutputPort() -> Port?
    {
        findPort(named: Self.outputPortName(selectedRouteIndex()))
    }
}
